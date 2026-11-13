"""Bounded quickdraw-cli release adapter. Never builds, lipo-merges or signs code."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
import subprocess
import tempfile
import urllib.parse
import urllib.request
import zipfile

from build_provenance import record, sha256

MAX_ARCHIVE = 512 * 1024 * 1024
MAX_EXPANDED = 1024 * 1024 * 1024
HOSTS = {"github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"}


def unique(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate JSON key: " + key)
        value[key] = item
    return value


def read_json(content):
    return json.loads(content, object_pairs_hook=unique)


def regular(path):
    path = Path(path).absolute()
    if not path.is_file() or any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError("required regular file: " + str(path))
    return path


def safe_destination(path):
    path = Path(path).absolute()
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError("destination must not traverse symlinks: " + str(path))
    return path


def configuration(root):
    value = read_json(regular(Path(root) / "cli/asset-lock.json").read_text(encoding="utf-8"))
    if (not isinstance(value, dict) or value.get("schema") != 1
            or value.get("repository") != "miyako/quickdraw-cli"
            or not re.fullmatch(r"\d+\.\d+\.\d+", value.get("version", ""))):
        raise ValueError("invalid external quickdraw-cli lock")
    if (not isinstance(value.get("source_revision"), str)
            or not re.fullmatch(r"[0-9a-f]{40}", value["source_revision"])
            or not isinstance(value.get("tag"), str)
            or not re.fullmatch(r"v?\d+\.\d+\.\d+", value["tag"])
            or set(value.get("assets", {})) != {"macos", "windows"}):
        raise ValueError("verified durable CLI release pins are pending; no CI-artifact or PATH fallback")
    for platform, entry in value["assets"].items():
        if (not isinstance(entry, dict)
                or set(entry) != {"url", "sha256", "target", "binary_sha256", "manifest_sha256"}
                or not all(isinstance(entry.get(key), str) for key in entry)):
            raise ValueError("invalid release asset lock entry: " + platform)
        for key in ("sha256", "binary_sha256", "manifest_sha256"):
            if not re.fullmatch(r"[0-9a-f]{64}", entry[key]):
                raise ValueError("missing pinned digest: " + key)
        if entry["target"] != {"macos": "universal-apple-darwin", "windows": "x86_64-pc-windows-msvc"}[platform]:
            raise ValueError("unsupported external CLI target identity")
        parsed = urllib.parse.urlsplit(entry["url"])
        prefix = "/miyako/quickdraw-cli/releases/download/" + value["tag"] + "/"
        if (parsed.scheme != "https" or parsed.netloc != "github.com"
                or parsed.query or parsed.fragment or not parsed.path.startswith(prefix)
                or not re.fullmatch(r"[A-Za-z0-9_.-]+\.zip", parsed.path[len(prefix):])):
            raise ValueError("asset URL must identify the exact public release ZIP")
    return value


def platform_for(target):
    if target in {"macos-arm64", "macos-x64"}:
        return "macos"
    if target == "windows-x64":
        return "windows"
    raise ValueError("unsupported CLI target: " + str(target))


def binary_header(data, platform):
    if platform == "windows":
        if len(data) < 64 or data[:2] != b"MZ":
            raise ValueError("Windows binary must be PE")
        offset = struct.unpack_from("<I", data, 60)[0]
        if (offset < 64 or len(data) < offset + 26 or data[offset:offset + 4] != b"PE\0\0"
                or struct.unpack_from("<H", data, offset + 4)[0] != 0x8664
                or struct.unpack_from("<H", data, offset + 24)[0] != 0x20B
                or not struct.unpack_from("<H", data, offset + 22)[0] & 2
                or struct.unpack_from("<H", data, offset + 22)[0] & 0x2000):
            raise ValueError("Windows binary must be an x64 PE32+ executable, not a DLL")
        return
    if len(data) < 8 or data[:4] not in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        raise ValueError("macOS binary must be universal Mach-O")
    wide = data[:4] == b"\xca\xfe\xba\xbf"
    count = struct.unpack_from(">I", data, 4)[0]
    entry_size = 32 if wide else 20
    if count != 2 or len(data) < 8 + count * entry_size:
        raise ValueError("exactly two macOS slices required")
    cpus, ranges = set(), []
    for index in range(count):
        position = 8 + index * entry_size
        cpu = struct.unpack_from(">I", data, position)[0]
        offset, size = struct.unpack_from(">QQ" if wide else ">II", data, position + 8)
        if (offset < 8 + count * entry_size or size < 32 or offset + size > len(data)
                or data[offset:offset + 4] != b"\xcf\xfa\xed\xfe"
                or struct.unpack_from("<I", data, offset + 4)[0] != cpu
                or struct.unpack_from("<I", data, offset + 12)[0] != 2
                or cpu in cpus or any(offset < end and start < offset + size for start, end in ranges)):
            raise ValueError("invalid macOS executable slice")
        cpus.add(cpu)
        ranges.append((offset, offset + size))
    if cpus != {0x01000007, 0x0100000C}:
        raise ValueError("macOS executable requires arm64 and x86_64")


def member_path(name):
    parts = name.split("/")
    if (not name or "\\" in name or ":" in name or PurePosixPath(name).is_absolute()
            or any(part in {"", ".", ".."} or part.endswith((".", " "))
                   or any(ord(c) < 32 for c in part)
                   or re.fullmatch(r"(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?", part)
                   for part in parts)):
        raise ValueError("unsafe archive member: " + name)
    return name


def verify_archive(archive, lock, platform):
    try:
        return _verify_archive(archive, lock, platform)
    except (zipfile.BadZipFile, UnicodeError, KeyError, TypeError, struct.error) as error:
        raise ValueError("invalid external CLI archive: " + str(error)) from error


def _verify_archive(archive, lock, platform):
    archive = regular(archive)
    entry = lock["assets"][platform]
    if archive.stat().st_size > MAX_ARCHIVE or sha256(archive) != entry["sha256"]:
        raise ValueError("external CLI archive SHA256/size mismatch")
    with zipfile.ZipFile(archive) as packed:
        files, identities, expanded = {}, set(), 0
        for info in packed.infolist():
            name = member_path(info.filename)
            mode = info.external_attr >> 16
            if (name.casefold() in identities or info.is_dir() or info.flag_bits & 1
                    or stat.S_IFMT(mode) not in {0, stat.S_IFREG} or mode & 0o7000):
                raise ValueError("duplicate or nonregular archive member")
            identities.add(name.casefold())
            expanded += info.file_size
            if expanded > MAX_EXPANDED or len(identities) > 10000:
                raise ValueError("external CLI archive expansion limit exceeded")
            files[name] = info
        if "manifest.json" not in files or files["manifest.json"].file_size > 8 * 1024 * 1024:
            raise ValueError("missing or oversized CLI manifest")
        manifest_bytes = packed.read("manifest.json")
        if hashlib.sha256(manifest_bytes).hexdigest() != entry["manifest_sha256"]:
            raise ValueError("CLI manifest digest mismatch")
        manifest = read_json(manifest_bytes)
        binary = "bin/quickdraw.exe" if platform == "windows" else "bin/quickdraw"
        expected = {"asset_schema": 1, "protocol": 1, "name": "quickdraw",
                    "version": lock["version"], "source_revision": lock["source_revision"],
                    "platform": platform, "target": entry["target"], "binary": binary,
                    "architecture": "universal" if platform == "macos" else "x86_64",
                    "sha256": entry["binary_sha256"]}
        if any(type(manifest.get(key)) is not type(value) or manifest.get(key) != value
               for key, value in expected.items()):
            raise ValueError("CLI manifest identity/provenance mismatch")
        if platform == "macos" and manifest.get("signed") is not True:
            raise ValueError("signed universal macOS release required")
        inventory = manifest.get("files")
        if not isinstance(inventory, dict) or set(inventory) != set(files) - {"manifest.json"}:
            raise ValueError("CLI manifest must inventory every regular member")
        for name, info in inventory.items():
            if (not isinstance(info, dict) or type(info.get("size")) is not int
                    or info["size"] != files[name].file_size
                    or not isinstance(info.get("sha256"), str)
                    or hashlib.sha256(packed.read(name)).hexdigest() != info["sha256"]):
                raise ValueError("CLI member hash/size mismatch: " + name)
        if (binary not in inventory or inventory[binary]["sha256"] != entry["binary_sha256"]
                or inventory[binary]["size"] != manifest.get("size")):
            raise ValueError("CLI binary identity mismatch")
        if not {"LICENSE", "Cargo.lock", "docs/cli.md", "docs/support.md"} <= set(files):
            raise ValueError("upstream license, lockfile and contracts must accompany executable")
        if not any(name.startswith("licenses/") and files[name].file_size for name in files):
            raise ValueError("upstream dependency/runtime redistribution notices required")
        if platform == "macos" and not (files[binary].external_attr >> 16) & 0o111:
            raise ValueError("macOS archive executable permission is missing")
        binary_header(packed.read(binary), platform)
        return manifest


def checked_url(url):
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname not in HOSTS
            or parsed.username or parsed.password or parsed.port not in (None, 443)):
        raise ValueError("external CLI download left approved HTTPS hosts")


class Redirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, newurl):
        checked_url(newurl)
        return super().redirect_request(request, response, code, message, headers, newurl)


def acquire(root, platform):
    root = Path(root).resolve()
    lock = configuration(root)
    entry = lock["assets"][platform]
    cache = safe_destination(root / "build/cli-assets" / entry["sha256"])
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / "asset.zip"
    if not archive.exists():
        checked_url(entry["url"])
        with tempfile.NamedTemporaryFile(dir=cache, delete=False) as output:
            temporary = Path(output.name)
            try:
                with urllib.request.build_opener(Redirect()).open(entry["url"], timeout=120) as response:
                    checked_url(response.geturl())
                    size = 0
                    while chunk := response.read(1024 * 1024):
                        size += len(chunk)
                        if size > MAX_ARCHIVE:
                            raise ValueError("external CLI archive download limit exceeded")
                        output.write(chunk)
                output.close()
                verify_archive(temporary, lock, platform)
                temporary.replace(archive)
            finally:
                temporary.unlink(missing_ok=True)
    manifest = verify_archive(archive, lock, platform)
    unpacked = safe_destination(cache / "unpacked")
    # Recreate only this hash-addressed, owned subtree, after full archive validation.
    if unpacked.exists():
        shutil.rmtree(unpacked)
    unpacked.mkdir()
    with zipfile.ZipFile(archive) as packed:
        for info in packed.infolist():
            destination = unpacked / info.filename
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(packed.read(info))
            destination.chmod(0o755 if info.filename == manifest["binary"] else 0o644)
    return lock, manifest, unpacked


def verify_signature(binary):
    subprocess.run(["codesign", "--verify", "--strict", "--all-architectures", "--verbose=2", str(binary)],
                   check=True, capture_output=True, timeout=60)
    detail = subprocess.run(["codesign", "-d", "--verbose=4", str(binary)],
                            check=True, capture_output=True, text=True, timeout=30).stderr
    if ("Authority=Developer ID Application:" not in detail or "TeamIdentifier=not set" in detail
            or not re.search(r"(?m)^TeamIdentifier=[A-Z0-9]{10}$", detail)
            or "runtime" not in detail or "Timestamp=" not in detail):
        raise ValueError("CLI requires timestamped hardened-runtime Developer ID Application signing")
    dependencies = subprocess.run(["otool", "-L", str(binary)], check=True,
                                  capture_output=True, text=True, timeout=30).stdout
    extra = [line.strip() for line in dependencies.splitlines()
             if " (compatibility version " in line
             and not line.strip().startswith(("/usr/lib/", "/System/Library/"))]
    if extra:
        raise ValueError("unbundled CLI native dependencies: " + repr(extra))


def install(root, target, test=True):
    from build_cli import native_target, smoke_test
    root = Path(root).resolve()
    platform = platform_for(target)
    if test and target != native_target():
        raise ValueError("native CLI tests require the actual matching host")
    lock, manifest, unpacked = acquire(root, platform)
    output = safe_destination(root / "build" / target)
    output.mkdir(parents=True, exist_ok=True)
    executable = safe_destination(output / Path(manifest["binary"]).name)
    shutil.copy2(unpacked / manifest["binary"], executable)
    if platform == "macos" and os.name != "nt":
        verify_signature(executable)
    if test:
        smoke_test(executable, lock["version"], root / "tests/cli-contract.json")
    status = record(root, target, executable, test, "external release; " + str(manifest.get("rustc", "")))
    status["upstream"] = {"source_revision": lock["source_revision"], "tag": lock["tag"],
                          "archive_sha256": lock["assets"][platform]["sha256"],
                          "binary_sha256": manifest["sha256"]}
    executable.with_name("build-manifest.json").write_text(json.dumps(status, indent=2) + "\n")
    return executable


def assemble(root):
    from build_provenance import verify
    root = Path(root).resolve()
    lock = configuration(root)
    executables = {}
    for target in ("macos-x64", "macos-arm64", "windows-x64"):
        binary = root / "build" / target / ("quickdraw.exe" if target == "windows-x64" else "quickdraw")
        verify(root, target, binary)
        expected = lock["assets"][platform_for(target)]["binary_sha256"]
        if sha256(binary) != expected:
            raise ValueError("installed binary differs from pinned upstream release")
        executables[target] = binary
    resources = safe_destination(root / "component/quickdraw/Resources")
    for platform, target, folder in (("macos", "macos-arm64", "macOS"), ("windows", "windows-x64", "Windows")):
        _, manifest, unpacked = acquire(root, platform)
        destination = safe_destination(resources / "bin" / folder / executables[target].name)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(executables[target], destination)
        notice = safe_destination(resources / "licenses/quickdraw-cli" / platform)
        if notice.exists():
            shutil.rmtree(notice)
        shutil.copytree(unpacked, notice, ignore=shutil.ignore_patterns("bin"))
    verify_signature(resources / "bin/macOS/quickdraw")
    safe_destination(resources / "quickdraw-assets.json").write_text(json.dumps(lock, indent=2) + "\n")
    return resources / "bin"


def verify_resources(root, component):
    lock = configuration(root)
    if read_json(regular(component / "Resources/quickdraw-assets.json").read_text()) != lock:
        raise ValueError("packaged upstream provenance differs from the release lock")
    for platform, folder, name in (("macos", "macOS", "quickdraw"), ("windows", "Windows", "quickdraw.exe")):
        binary = regular(component / "Resources/bin" / folder / name)
        if sha256(binary) != lock["assets"][platform]["binary_sha256"]:
            raise ValueError("packaged external CLI binary hash mismatch")
        notices = component / "Resources/licenses/quickdraw-cli" / platform
        manifest_path = regular(notices / "manifest.json")
        if sha256(manifest_path) != lock["assets"][platform]["manifest_sha256"]:
            raise ValueError("packaged upstream manifest digest mismatch")
        manifest = read_json(manifest_path.read_text())
        for name, expected in manifest["files"].items():
            if name == manifest["binary"]:
                continue
            member_path(name)
            path = regular(notices / name)
            if path.stat().st_size != expected["size"] or sha256(path) != expected["sha256"]:
                raise ValueError("redistribution content changed: " + name)
    return lock
