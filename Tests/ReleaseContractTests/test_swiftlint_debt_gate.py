from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GATE = ROOT / "scripts" / "swiftlint_debt_gate.py"


class SwiftLintDebtGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.baseline = {
            "schemaVersion": 1,
            "areas": {
                "production": {
                    "total": 2,
                    "rules": {"file_length": 2},
                },
                "tests": {
                    "total": 1,
                    "rules": {"function_body_length": 1},
                },
            },
        }

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_report_at_or_below_every_ceiling_passes(self) -> None:
        result = self.run_gate(
            [
                self.violation("Sources/Cadence/App.swift", "file_length"),
                self.violation(
                    "Tests/CadenceTests/AppTests.swift",
                    "function_body_length",
                ),
            ]
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("production 1/2", result.stdout)
        self.assertIn("tests 1/1", result.stdout)

    def test_new_rule_fails_even_when_area_total_does_not_grow(self) -> None:
        result = self.run_gate(
            [
                self.violation("Sources/Cadence/App.swift", "file_length"),
                self.violation("Sources/Cadence/Feature.swift", "nesting"),
            ]
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("production nesting: 1 > 0", result.stderr)

    def test_existing_rule_growth_reports_the_exact_excess(self) -> None:
        result = self.run_gate(
            [
                self.violation("Sources/Cadence/One.swift", "file_length"),
                self.violation("Sources/Cadence/Two.swift", "file_length"),
                self.violation("Sources/Cadence/Three.swift", "file_length"),
            ]
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("production total: 3 > 2", result.stderr)
        self.assertIn("production file_length: 3 > 2", result.stderr)

    def test_malformed_baseline_fails_with_an_actionable_error(self) -> None:
        self.baseline["schemaVersion"] = 99

        result = self.run_gate([])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported baseline schemaVersion: 99", result.stderr)

    def run_gate(self, report: list[dict[str, object]]) -> subprocess.CompletedProcess[str]:
        baseline_path = self.root / "baseline.json"
        report_path = self.root / "report.json"
        baseline_path.write_text(json.dumps(self.baseline), encoding="utf-8")
        report_path.write_text(json.dumps(report), encoding="utf-8")
        return subprocess.run(
            [
                sys.executable,
                "-I",
                "-B",
                str(GATE),
                "--baseline",
                str(baseline_path),
                "--report",
                str(report_path),
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    def violation(self, file: str, rule_id: str) -> dict[str, object]:
        return {
            "character": 1,
            "file": str(self.root / file),
            "line": 1,
            "reason": "fixture violation",
            "rule_id": rule_id,
            "severity": "Warning",
            "type": "Fixture",
        }


if __name__ == "__main__":
    unittest.main()
