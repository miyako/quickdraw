"""Opt-in real 4D binding unit tests, without CLI execution or package acceptance."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get("TOOL4D_BINDING_TEST"), "opt-in real 4D binding unit tests")
class BindingRuntimeTests(unittest.TestCase):
    def test_real_4d_type_guards_arguments_and_protocol(self):
        (ROOT / "build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="binding host ", dir=ROOT / "build") as temporary:
            root = Path(temporary)
            host = root / "Host"
            shutil.copytree(ROOT / "tests/host", host)
            (host / "environment4d.json").unlink()
            shutil.copytree(ROOT / "component/quickdraw", host / "Components/quickdraw.4dbase",
                            ignore=shutil.ignore_patterns("DerivedData", "Libraries", "bin", "quickdraw-cli"))
            output = root / "binding-status.json"
            tool = Path(os.environ["TOOL4D_BINDING_TEST"]).resolve()
            started = time.monotonic()
            subprocess.run([str(tool), str(host / "Project/Host.4DProject"), "--skip-onstartup",
                            "--startup-method=Binding_contract", "--dataless",
                            "--user-param=" + str(output)], check=True, timeout=60)
            self.assertTrue(output.is_file(), "real host did not finish binding unit tests")
            report = json.loads(output.read_text())
            (ROOT / "build/binding-unit-status.json").write_text(json.dumps(report, indent=2) + "\n")
            self.assertIs(report["finished"], True)
            self.assertIs(report["compiled"], False)
            self.assertEqual(len(report["argumentFailures"]), 33)
            for result in report["argumentFailures"]:
                self.assertIs(result["ok"], False)
                self.assertEqual(result["error"]["code"], "invalid_argument")
                self.assertNotIn("exitCode", result)
            self.assertEqual(len(report["protocolFailures"]), 10)
            for result in report["protocolFailures"]:
                self.assertIs(result["ok"], False)
                self.assertEqual(result["error"]["code"], "invalid_protocol")
                self.assertEqual(result["exitCode"], 0)
                self.assertNotIn("value", result)
            self.assertEqual(report["defaultArguments"]["arguments"],
                             ["inspect", "--input", '/tmp/space 日本語 " quote.pict'])
            args = report["options"]["arguments"]
            self.assertEqual(args[:5], ["convert", "--input", "/tmp/input.pict", "--output", "/tmp/output.png"])
            self.assertNotIn("--data-fork", args)
            self.assertIn("--overwrite", args)
            values = {key: args[index + 1] for index, key in enumerate(args)
                      if key.startswith("--") and key != "--overwrite"}
            self.assertEqual(values, {
                "--input": "/tmp/input.pict", "--output": "/tmp/output.png",
                "--container": "raw", "--resource-id": "-128", "--format": "png",
                "--fidelity": "approximate", "--printer-comments": "apple-portable",
                "--vector-policy": "reject", "--width": "16", "--height": "24", "--dpi": "144.5",
                "--background": "112233", "--highlight": "abcdef", "--font-map": "/tmp/font map.json",
                "--max-input-bytes": "18446744073709551615", "--max-pixels": "16000000",
                "--max-decoded-bytes": "134217728", "--max-operations": "100000", "--max-work": "100000000"})
            self.assertIs(report["version"]["ok"], True)
            self.assertEqual(report["version"]["value"]["future"], "preserved")
            self.assertEqual(report["converterFailure"]["failureKind"], "converter")
            self.assertEqual(report["converterFailure"]["error"],
                             {"code": "unsupported", "message": "matte", "offset": 40,
                              "opcode": 33280, "future": "retained"})
            self.assertEqual(report["mismatchedFailure"]["error"]["code"], "invalid_protocol")
            if os.name != "nt":
                self.assertGreaterEqual(time.monotonic() - started, 29)
                self.assertIs(report["timeout"]["ok"], False)
                self.assertIn(report["timeout"]["error"]["code"], ("process_error", "process_terminated"))
