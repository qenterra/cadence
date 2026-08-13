from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from release_contract import environment_values, validate_product_surfaces  # noqa: E402


class CadenceReleaseContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        manifest = {
            "schemaVersion": 1,
            "product": {
                "name": "Cadence",
                "artifactStem": "Cadence",
                "bundleIdentifier": "com.qenterra.cadence",
                "humanReleaseName": "Cadence 0.2.0 Beta 1 (2)",
            },
            "release": {
                "marketingVersion": "0.2.0",
                "build": 2,
                "channel": "beta",
                "iteration": 1,
                "version": "0.2.0-beta.1",
                "tag": "v0.2.0-beta.1",
            },
            "platform": {
                "name": "macOS",
                "minimumVersion": "26.0",
                "architecture": "arm64",
            },
            "distribution": {
                "signing": "ad-hoc",
                "notarized": False,
                "gatekeeperDisclosure": True,
            },
            "installer": {
                "format": "dmg",
                "style": "soft-graphite-monochrome",
                "applicationsAlias": True,
            },
            "artifacts": {
                "installer": "Cadence-0.2.0-beta.1-arm64.dmg",
                "update": "Cadence-0.2.0-beta.1-arm64.zip",
                "checksums": "Cadence-0.2.0-beta.1-SHA256SUMS.txt",
            },
        }
        (self.root / "qds-release.json").write_text(json.dumps(manifest), encoding="utf-8")
        (self.root / "project.yml").write_text(
            'deploymentTarget:\n  macOS: "26.0"\n'
            'MARKETING_VERSION: "0.2.0"\n'
            'CURRENT_PROJECT_VERSION: "2"\n'
            'PRODUCT_BUNDLE_IDENTIFIER: com.qenterra.cadence\n',
            encoding="utf-8",
        )
        (self.root / "README.md").write_text(
            "Version 0.2.0-beta.1\n"
            "Cadence-0.2.0-beta.1-arm64.dmg\n"
            "This ad-hoc beta is not notarized and macOS may show Gatekeeper friction.\n",
            encoding="utf-8",
        )
        (self.root / "CHANGELOG.md").write_text(
            "## [0.2.0-beta.1] - 2026-08-13\n",
            encoding="utf-8",
        )
        (self.root / "docs").mkdir()
        (self.root / "docs" / "UPDATES.md").write_text(
            "Cadence 0.2.0 Beta 1 (2)\n"
            "v0.2.0-beta.1\n"
            "Cadence-0.2.0-beta.1-arm64.dmg\n"
            "Cadence-0.2.0-beta.1-arm64.zip\n"
            "Cadence-0.2.0-beta.1-SHA256SUMS.txt\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_aligned_product_surfaces_pass(self) -> None:
        self.assertEqual(validate_product_surfaces(self.root), [])

    def test_version_and_artifact_drift_fail_together(self) -> None:
        project = self.root / "project.yml"
        project.write_text(
            project.read_text(encoding="utf-8").replace('"0.2.0"', '"0.3.0"'),
            encoding="utf-8",
        )
        readme = self.root / "README.md"
        readme.write_text(
            readme.read_text(encoding="utf-8").replace(
                "Cadence-0.2.0-beta.1-arm64.dmg",
                "Cadence-latest.dmg",
            ),
            encoding="utf-8",
        )

        errors = "\n".join(validate_product_surfaces(self.root))

        self.assertIn("MARKETING_VERSION", errors)
        self.assertIn("README.md must include Cadence-0.2.0-beta.1-arm64.dmg", errors)

    def test_manifest_emits_packaging_values_without_renaming(self) -> None:
        values = environment_values(self.root)

        self.assertEqual(values["PUBLIC_VERSION"], "0.2.0-beta.1")
        self.assertEqual(values["TAG"], "v0.2.0-beta.1")
        self.assertEqual(values["DMG_NAME"], "Cadence-0.2.0-beta.1-arm64.dmg")
        self.assertEqual(values["ZIP_NAME"], "Cadence-0.2.0-beta.1-arm64.zip")
        self.assertEqual(
            values["CHECKSUMS_NAME"],
            "Cadence-0.2.0-beta.1-SHA256SUMS.txt",
        )


if __name__ == "__main__":
    unittest.main()
