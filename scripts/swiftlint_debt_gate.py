#!/usr/bin/env python3
"""Reject SwiftLint warning growth relative to a reviewed baseline."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any


AREA_NAMES = ("production", "tests")


class GateError(ValueError):
    """Raised when gate input cannot be evaluated safely."""


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise GateError(f"cannot read {path}: {error}") from error


def validate_baseline(value: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(value, dict):
        raise GateError("baseline must be a JSON object")
    version = value.get("schemaVersion")
    if version != 1:
        raise GateError(f"unsupported baseline schemaVersion: {version}")
    areas = value.get("areas")
    if not isinstance(areas, dict):
        raise GateError("baseline areas must be a JSON object")
    for area_name in AREA_NAMES:
        validate_area_baseline(area_name, areas.get(area_name))
    return areas


def validate_area_baseline(name: str, value: Any) -> None:
    if not isinstance(value, dict):
        raise GateError(f"baseline area {name} must be a JSON object")
    total = value.get("total")
    rules = value.get("rules")
    if not isinstance(total, int) or total < 0:
        raise GateError(f"baseline area {name} total must be a non-negative integer")
    if not isinstance(rules, dict) or not all(
        isinstance(rule, str)
        and isinstance(count, int)
        and count >= 0
        for rule, count in rules.items()
    ):
        raise GateError(f"baseline area {name} rules must contain non-negative integers")
    if sum(rules.values()) != total:
        raise GateError(f"baseline area {name} rule counts do not equal total {total}")


def report_counts(value: Any) -> dict[str, Counter[str]]:
    if not isinstance(value, list):
        raise GateError("SwiftLint report must be a JSON array")
    counts = {name: Counter() for name in AREA_NAMES}
    for index, violation in enumerate(value):
        if not isinstance(violation, dict):
            raise GateError(f"SwiftLint report row {index} must be a JSON object")
        file = violation.get("file")
        rule_id = violation.get("rule_id")
        if not isinstance(file, str) or not isinstance(rule_id, str):
            raise GateError(f"SwiftLint report row {index} is missing file or rule_id")
        counts[classify_area(file)][rule_id] += 1
    return counts


def classify_area(file: str) -> str:
    parts = Path(file).parts
    if "Sources" in parts:
        return "production"
    if "Tests" in parts:
        return "tests"
    raise GateError(f"SwiftLint report contains an unclassified file: {file}")


def debt_increases(
    baseline: dict[str, dict[str, Any]],
    actual: dict[str, Counter[str]],
) -> list[str]:
    increases: list[str] = []
    for area_name in AREA_NAMES:
        area_baseline = baseline[area_name]
        area_actual = actual[area_name]
        actual_total = sum(area_actual.values())
        if actual_total > area_baseline["total"]:
            increases.append(
                f"{area_name} total: {actual_total} > {area_baseline['total']}"
            )
        for rule_id, count in sorted(area_actual.items()):
            ceiling = area_baseline["rules"].get(rule_id, 0)
            if count > ceiling:
                increases.append(f"{area_name} {rule_id}: {count} > {ceiling}")
    return increases


def summary(
    baseline: dict[str, dict[str, Any]],
    actual: dict[str, Counter[str]],
) -> str:
    areas = ", ".join(
        f"{name} {sum(actual[name].values())}/{baseline[name]['total']}"
        for name in AREA_NAMES
    )
    return f"SwiftLint debt: {areas}."


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        baseline = validate_baseline(load_json(arguments.baseline))
        actual = report_counts(load_json(arguments.report))
    except GateError as error:
        print(f"SwiftLint debt gate error: {error}", file=sys.stderr)
        return 2
    increases = debt_increases(baseline, actual)
    if increases:
        print("SwiftLint debt increased:", file=sys.stderr)
        for increase in increases:
            print(f"- {increase}", file=sys.stderr)
        return 1
    print(summary(baseline, actual))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
