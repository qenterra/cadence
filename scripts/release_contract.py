#!/usr/bin/env python3
"""Validate Cadence release surfaces against qds-release.json."""

from __future__ import annotations

import argparse
import json
import re
import shlex
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def load_manifest(root: Path) -> dict[str, Any]:
    return json.loads((root / "qds-release.json").read_text(encoding="utf-8"))


def environment_values(root: Path = ROOT) -> dict[str, str]:
    data = load_manifest(root)
    product = data["product"]
    release = data["release"]
    platform = data["platform"]
    artifacts = data["artifacts"]
    return {
        "PRODUCT_NAME": str(product["name"]),
        "BUNDLE_IDENTIFIER": str(product["bundleIdentifier"]),
        "HUMAN_RELEASE_NAME": str(product["humanReleaseName"]),
        "MARKETING_VERSION": str(release["marketingVersion"]),
        "BUILD_NUMBER": str(release["build"]),
        "CHANNEL": str(release["channel"]),
        "PUBLIC_VERSION": str(release["version"]),
        "TAG": str(release["tag"]),
        "MINIMUM_MACOS": str(platform["minimumVersion"]),
        "ARCHITECTURE": str(platform["architecture"]),
        "DMG_NAME": str(artifacts["installer"]),
        "ZIP_NAME": str(artifacts["update"]),
        "CHECKSUMS_NAME": str(artifacts["checksums"]),
    }


def require_text(path: Path, expected: str, label: str, errors: list[str]) -> None:
    if not path.is_file():
        errors.append(f"{path.name} is missing")
        return
    if expected not in path.read_text(encoding="utf-8"):
        errors.append(f"{label} must include {expected}")


def validate_product_surfaces(root: Path = ROOT) -> list[str]:
    root = root.resolve()
    data = load_manifest(root)
    values = environment_values(root)
    errors: list[str] = []

    project_path = root / "project.yml"
    if not project_path.is_file():
        errors.append("project.yml is missing")
    else:
        project = project_path.read_text(encoding="utf-8")
        expected_settings = {
            "MARKETING_VERSION": f'"{values["MARKETING_VERSION"]}"',
            "CURRENT_PROJECT_VERSION": f'"{values["BUILD_NUMBER"]}"',
            "PRODUCT_BUNDLE_IDENTIFIER": values["BUNDLE_IDENTIFIER"],
        }
        for key, expected in expected_settings.items():
            pattern = rf"^\s*{re.escape(key)}:\s*{re.escape(expected)}\s*$"
            if re.search(pattern, project, flags=re.MULTILINE) is None:
                errors.append(f"project.yml {key} must be {expected}")
        deployment_pattern = rf'^\s*macOS:\s*"{re.escape(values["MINIMUM_MACOS"])}"\s*$'
        if re.search(deployment_pattern, project, flags=re.MULTILINE) is None:
            errors.append(
                f'project.yml macOS deployment target must be "{values["MINIMUM_MACOS"]}"'
            )

    readme = root / "README.md"
    require_text(readme, f'Version {values["PUBLIC_VERSION"]}', "README.md", errors)
    require_text(readme, values["DMG_NAME"], "README.md", errors)
    if data.get("distribution", {}).get("gatekeeperDisclosure") is True:
        require_text(readme, "not notarized", "README.md Gatekeeper disclosure", errors)
        require_text(readme, "Gatekeeper", "README.md Gatekeeper disclosure", errors)

    changelog = root / "CHANGELOG.md"
    require_text(
        changelog,
        f'## [{values["PUBLIC_VERSION"]}]',
        "CHANGELOG.md",
        errors,
    )

    updates = root / "docs" / "UPDATES.md"
    for expected in (
        values["HUMAN_RELEASE_NAME"],
        values["TAG"],
        values["DMG_NAME"],
        values["ZIP_NAME"],
        values["CHECKSUMS_NAME"],
    ):
        require_text(updates, expected, "docs/UPDATES.md", errors)

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Cadence release surface validator")
    parser.add_argument("command", choices=("check", "env"), nargs="?", default="check")
    parser.add_argument("--root", type=Path, default=ROOT)
    arguments = parser.parse_args()

    if arguments.command == "env":
        for key, value in environment_values(arguments.root).items():
            if "\n" in value or "\r" in value:
                parser.error(f"{key} contains a newline")
            print(f"{key}={shlex.quote(value)}")
        return 0

    errors = validate_product_surfaces(arguments.root)
    if errors:
        for error in errors:
            print(f"- {error}")
        return 1
    values = environment_values(arguments.root)
    print(f'Cadence release contract passed for {values["PUBLIC_VERSION"]} ({values["BUILD_NUMBER"]})')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
