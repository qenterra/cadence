#!/usr/bin/env python3

"""Verify that compiler-emitted localization keys match the string catalog."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def load_json(path: Path) -> dict[str, object]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"Could not read localization metadata at {path}: {error}") from error


def extracted_keys(metadata_paths: list[Path]) -> set[str]:
    keys: set[str] = set()
    for path in metadata_paths:
        document = load_json(path)
        tables = document.get("tables", {})
        if not isinstance(tables, dict):
            raise RuntimeError(f"Invalid localization tables in {path}")
        entries = tables.get("Localizable", [])
        if not isinstance(entries, list):
            raise RuntimeError(f"Invalid Localizable table in {path}")
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("key"), str):
                raise RuntimeError(f"Invalid localization entry in {path}")
            keys.add(entry["key"])
    return keys


def verify(catalog_path: Path, metadata_paths: list[Path]) -> None:
    catalog = load_json(catalog_path)
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        raise RuntimeError(f"Invalid string catalog at {catalog_path}")

    emitted = extracted_keys(metadata_paths)
    catalog_keys = set(strings)
    missing = sorted(emitted - catalog_keys)
    orphaned = sorted(
        key
        for key, value in strings.items()
        if key not in emitted
        and isinstance(value, dict)
        and value.get("extractionState") != "stale"
    )

    failures: list[str] = []
    if missing:
        failures.append("Missing catalog keys: " + ", ".join(repr(key) for key in missing))
    if orphaned:
        failures.append(
            "Non-stale catalog keys absent from compiler metadata: "
            + ", ".join(repr(key) for key in orphaned)
        )
    if failures:
        raise RuntimeError("\n".join(failures))

    print(f"Localization catalog is synchronized ({len(emitted)} active keys).")


def main() -> int:
    if len(sys.argv) < 3:
        print(
            "Usage: verify_localization.py <catalog> <stringsdata> [...]",
            file=sys.stderr,
        )
        return 2
    try:
        verify(Path(sys.argv[1]), [Path(argument) for argument in sys.argv[2:]])
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
