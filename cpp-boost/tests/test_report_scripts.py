"""Run the report from an unrelated attempt directory, as the process executor does."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class ReportScriptsTest(unittest.TestCase):
    def test_complete_pipeline_from_attempt_directory(self):
        with tempfile.TemporaryDirectory(prefix="rota-report-") as temporary:
            project = Path(temporary)
            scripts = project / "scripts"
            shutil.copytree(Path(__file__).resolve().parents[1] / "scripts", scripts)
            attempt = project / "data" / "runs" / "attempt"
            attempt.mkdir(parents=True)
            for name in ("extract", "transform", "load"):
                subprocess.run([sys.executable, str(scripts / f"{name}.py")], cwd=attempt,
                               env={**os.environ, "TARGET": "warehouse"}, check=True, capture_output=True)
            report = json.loads((project / "data" / "nightly-report" / "report.json").read_text(encoding="utf-8"))
            self.assertEqual(report["target"], "warehouse")
            self.assertEqual(report["total_requests"], 260)
            self.assertEqual(report["total_errors"], 3)
            self.assertEqual(report["services"]["api"], {"requests": 180, "errors": 2})


if __name__ == "__main__":
    unittest.main()
