"""Native tests of the externally verified executable, never a second CLI build."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_cli import native_target
from make_fixtures import write_fixtures


class NativeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get("TEST_CLI_LANGUAGE") == "none":
            raise unittest.SkipTest("native executable checks explicitly disabled")
        target = native_target()
        cls.executable = ROOT / "build" / target / ("quickdraw.exe" if os.name == "nt" else "quickdraw")
        if not cls.executable.is_file():
            raise RuntimeError("missing verified CLI; run scripts/build_cli.py --target " + target)
        from build_provenance import verify
        verify(ROOT, target, cls.executable)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="quickdraw 日本語 ", dir=ROOT / "build")
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        write_fixtures(self.folder)
        self.input = self.folder / "rectangle.pict"

    def invoke(self, args, code=0):
        completed = subprocess.run([str(self.executable), *map(str, args)], capture_output=True, timeout=30)
        self.assertEqual(completed.returncode, code, completed.stderr)
        stream = completed.stdout if code == 0 else completed.stderr
        self.assertEqual(completed.stderr if code == 0 else completed.stdout, b"")
        self.assertTrue(stream.endswith(b"\n"))
        self.assertEqual(stream.count(b"\n"), 1)
        result = json.loads(stream)
        self.assertEqual(result["protocol"], 1)
        return result

    def test_version_and_capabilities(self):
        from external_cli import configuration
        self.assertEqual(self.invoke(["--version"]), {"protocol": 1, "version": configuration(ROOT)["version"]})
        value = self.invoke(["capabilities"])
        self.assertEqual(value["formats"], ["png", "svg", "pdf"])
        self.assertFalse(value["fidelity"]["classic_oracle_validated"])
        self.assertFalse(value["quicktime_separate_matte"])
        self.assertFalse(value["outline_fonts"]["nonzero_linejustify"])

    def test_outputs_warning_hashes_and_explicit_vector_policy(self):
        original = self.input.read_bytes()
        for format, policy in (("png", None), ("svg", "preserve"), ("pdf", "preserve"),
                               ("svg", "raster"), ("pdf", "raster")):
            with self.subTest(format=format, policy=policy):
                output = self.folder / (f"{policy} 日本語 ' ; & output.{format}")
                args = ["convert", "--input", self.input, "--output", output]
                if policy:
                    args += ["--vector-policy", policy]
                value = self.invoke(args)
                self.assertEqual(value["sha256"], hashlib.sha256(output.read_bytes()).hexdigest())
                self.assertEqual(value["input_sha256"], hashlib.sha256(original).hexdigest())
                self.assertEqual((value["width"], value["height"]), (8, 8))
                self.assertIn("unverified_fidelity", [item["code"] for item in value["diagnostics"]])
        self.assertEqual(self.input.read_bytes(), original)

    def test_no_clobber_and_source_alias_protection(self):
        output = self.folder / "existing.png"
        output.write_bytes(b"preserve me")
        self.invoke(["convert", "--input", self.input, "--output", output], 3)
        self.assertEqual(output.read_bytes(), b"preserve me")
        value = self.invoke(["convert", "--input", self.input, "--output", self.input,
                             "--format", "png", "--overwrite"], 3)
        self.assertEqual(value["error"]["code"], "output_conflict")
        alias = self.folder / "alias.png"
        os.link(self.input, alias)
        self.invoke(["convert", "--input", self.input, "--output", alias, "--overwrite"], 3)
        self.assertEqual(self.input.read_bytes(), alias.read_bytes())

    def test_unsupported_malformed_limits_and_approximation(self):
        output = self.folder / "out.png"
        for source, options, code, error in (
            ("text.pict", [], 5, "unsupported"),
            ("malformed.pict", [], 4, "malformed"),
            ("rectangle.pict", ["--max-pixels", "1"], 6, "resource_limit"),
            ("oval.pict", [], 5, "unsupported"),
        ):
            with self.subTest(source=source, options=options):
                value = self.invoke(["convert", "--input", self.folder / source, "--output", output, *options], code)
                self.assertEqual(value["error"]["code"], error)
                self.assertFalse(output.exists())
        value = self.invoke(["convert", "--input", self.folder / "oval.pict", "--output", output,
                             "--fidelity", "approximate"])
        self.assertIn("approximation", [item["code"] for item in value["diagnostics"]])

    def test_options_and_literal_paths(self):
        name = 'space 日本語 " quote \\ slash.pict' if os.name != "nt" else "space 日本語.pict"
        source = self.folder / name
        shutil.copyfile(self.input, source)
        inspected = self.invoke(["inspect", "--input", source, "--container", "raw", "--data-fork"])
        self.assertEqual(inspected["inspection"]["pict_version"], 1)
        inventory = self.invoke(["list-pictures", "--input", source, "--container", "raw"])
        self.assertEqual(len(inventory["inventory"]["pictures"]), 1)
        value = self.invoke(["convert", "--input", source, "--output", self.folder / "options.png",
                             "--container", "raw", "--width", "16", "--height", "24", "--dpi", "144",
                             "--background", "112233", "--highlight", "abcdef",
                             "--font-map", self.folder / "font-map.json",
                             "--max-input-bytes", "67108864", "--max-pixels", "16000000",
                             "--max-decoded-bytes", "134217728", "--max-operations", "100000",
                             "--max-work", "100000000", "--printer-comments", "ignore"])
        self.assertEqual((value["width"], value["height"], value["dpi"]), (16, 24, 144))
        self.invoke(["inspect", "--input", source, "--resource-id", "1", "--data-fork"], 2)


if __name__ == "__main__":
    unittest.main()
