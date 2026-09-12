from __future__ import annotations

import json
import itertools
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from release_contract import (  # noqa: E402
    ReleaseContractError,
    environment_values,
    validate_product_surfaces,
    validate_public_release_environment,
)


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
        (self.root / "release-contract.json").write_text(json.dumps(manifest), encoding="utf-8")
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
            "This ad-hoc beta is not notarized and macOS may show Gatekeeper friction.\n"
            "Use manual download; no automatic update is published.\n",
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

    def test_public_release_rejects_missing_credentials(self) -> None:
        self.set_distribution("developer-id", True, False)
        errors = validate_public_release_environment(self.root, {})

        self.assertIn("CADENCE_DEVELOPER_ID_APPLICATION is required", errors)
        self.assertIn("CADENCE_DEVELOPMENT_TEAM is required", errors)
        self.assertIn("CADENCE_NOTARY_KEYCHAIN_PROFILE is required", errors)

    def test_public_ad_hoc_release_accepts_disclosure_without_credentials(self) -> None:
        self.assertEqual(validate_public_release_environment(self.root, {}), [])
        self.assertEqual(environment_values(self.root)["DISTRIBUTION_SIGNING"], "ad-hoc")

    def test_public_ad_hoc_release_requires_each_disclosure(self) -> None:
        readme = self.root / "README.md"
        original = readme.read_text(encoding="utf-8")
        for disclosure in ("ad-hoc", "not notarized", "Gatekeeper", "manual download"):
            with self.subTest(disclosure=disclosure):
                readme.write_text(original.replace(disclosure, "omitted"), encoding="utf-8")
                self.assertIn(
                    f"README.md Gatekeeper disclosure must include {disclosure}",
                    validate_public_release_environment(self.root, {}),
                )

    def test_mixed_distribution_claims_fail_before_packaging(self) -> None:
        for signing, notarized, disclosure in itertools.product(
            ("developer-id", "ad-hoc", "unknown"), (False, True), (False, True)
        ):
            if (signing, notarized, disclosure) in {
                ("developer-id", True, False), ("ad-hoc", False, True)
            }:
                continue
            with self.subTest(signing=signing, notarized=notarized, disclosure=disclosure):
                self.set_distribution(signing, notarized, disclosure)
                with self.assertRaisesRegex(ReleaseContractError, "mixed claims"):
                    environment_values(self.root)
                with self.assertRaisesRegex(ReleaseContractError, "mixed claims"):
                    validate_public_release_environment(self.root, {})

    def set_distribution(self, signing: str, notarized: bool, disclosure: bool) -> None:
        path = self.root / "release-contract.json"
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest["distribution"] = {
            "signing": signing,
            "notarized": notarized,
            "gatekeeperDisclosure": disclosure,
        }
        path.write_text(json.dumps(manifest), encoding="utf-8")

    def test_public_release_accepts_complete_distribution_contract(self) -> None:
        manifest_path = self.root / "release-contract.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["distribution"] = {
            "signing": "developer-id",
            "notarized": True,
            "gatekeeperDisclosure": False,
        }
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        environment = {
            "CADENCE_DEVELOPER_ID_APPLICATION": "Developer ID Application: QenTerra",
            "CADENCE_DEVELOPMENT_TEAM": "ABCDE12345",
            "CADENCE_NOTARY_KEYCHAIN_PROFILE": "cadence-notary",
        }

        self.assertEqual(
            validate_public_release_environment(self.root, environment),
            [],
        )


class DependencyResolutionContractTests(unittest.TestCase):
    def test_sparkle_resolution_uses_security_fixed_release(self) -> None:
        project = (ROOT / "project.yml").read_text(encoding="utf-8")
        resolved = json.loads(
            (
                ROOT
                / "Cadence.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            ).read_text(encoding="utf-8")
        )

        self.assertIn("exactVersion: 2.9.6", project)
        sparkle = next(pin for pin in resolved["pins"] if pin["identity"] == "sparkle")
        self.assertEqual(sparkle["state"]["version"], "2.9.6")
        self.assertEqual(
            sparkle["state"]["revision"],
            "ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a",
        )


class ReleaseScriptContractTests(unittest.TestCase):
    def test_developer_id_mode_retains_notarization_and_validation(self) -> None:
        script = (ROOT / "scripts" / "prepare_release.sh").read_text(encoding="utf-8")

        self.assertIn('CADENCE_RELEASE_MODE', script)
        self.assertIn('notarytool submit', script)
        self.assertGreaterEqual(script.count('stapler staple'), 2)
        self.assertGreaterEqual(script.count('stapler validate'), 2)
        self.assertIn('spctl --assess', script)
        self.assertIn('ENABLE_HARDENED_RUNTIME=YES', script)

    def test_macos_27_disk_image_operations_use_diskutil(self) -> None:
        script = (ROOT / "scripts" / "create_dmg.sh").read_text(encoding="utf-8")

        self.assertIn('/usr/sbin/diskutil image info', script)
        self.assertIn('/usr/sbin/diskutil image attach', script)
        self.assertIn('/usr/sbin/diskutil image create blank', script)
        self.assertIn('/usr/sbin/diskutil image create from', script)
        self.assertIn('/usr/sbin/diskutil eject', script)
        self.assertIn('legacy_hdiutil_', script)
        modern_branch = script.split('if (( macos_major >= 27 ));', 1)[1]
        self.assertIn('"$layout_writer"', modern_branch)

    def test_screenshot_update_promotes_complete_temporary_candidates(self) -> None:
        script = (ROOT / "scripts" / "update_screenshots.sh").read_text(encoding="utf-8")

        self.assertIn('CadenceVisualRegression/update', script)
        self.assertIn('candidate_dir="${TMPDIR:?}', script)
        self.assertIn('expected_candidate_count="91"', script)
        self.assertIn('-only-testing:CadenceTests/AllTracksVisualAcceptanceTests', script)
        self.assertIn('candidate_count', script)
        self.assertIn('cp -f "$candidate_dir"/*.png', script)

if __name__ == "__main__":
    unittest.main()
