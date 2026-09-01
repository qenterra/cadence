#!/usr/bin/env python3
"""Verify the Cadence UI ownership inventory against live Swift declarations."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


VISUAL_PROTOCOLS = {
    "View",
    "ViewModifier",
    "ButtonStyle",
    "Layout",
    "NSViewRepresentable",
    "NSViewControllerRepresentable",
}
APPKIT_BASES = {"NSView", "NSTableView", "NSTableCellView", "MTKView"}
VISUAL_KINDS = VISUAL_PROTOCOLS | APPKIT_BASES | {"MTKViewDelegate"}
UI_SOURCE_ROOTS = ("Components", "DesignSystem", "Features")
CONCRETE_BASE_PRECEDENCE = ("NSTableCellView", "NSTableView", "MTKView", "NSView")
MANIFEST_SCHEMA_VERSION = 2
MANIFEST_SOURCE_ROOT = "Sources/Cadence"
TOP_LEVEL_FIELDS = frozenset({"schemaVersion", "sourceRoot", "components"})
COMPONENT_FIELDS = frozenset(
    {
        "path",
        "symbol",
        "kind",
        "line",
        "classification",
        "deliveryProduct",
        "sharedSymbol",
        "remainingCadenceSymbol",
        "dependencies",
        "states",
        "wave",
        "evidence",
    }
)
DEPENDENCY_FIELDS = frozenset({"data", "actions"})
STATE_FIELDS = frozenset({"appearance", "motion", "accessibility", "interaction"})
EVIDENCE_FIELDS = frozenset({"status", "detail", "references"})
DEPENDENCY_ENTRY_FIELDS = frozenset({"symbol", "role"})
MIGRATION_WAVES = {
    "wave-2-core",
    "wave-3-feedback-settings",
    "wave-4-media",
    "wave-5-player-lyrics",
    "wave-6-adapters",
    "wave-7-product",
}
STATE_VALUES = {
    "system", "light", "dark", "increased-contrast", "reduced-transparency", "not-applicable",
    "static", "animated", "reduced-motion",
    "voiceover", "keyboard-focus", "native-semantics",
    "default", "hover", "pressed", "selected", "disabled", "drag", "drop", "read-only",
}
DECLARATION = re.compile(
    r"(?m)^[ \t]*(?:(?:private|fileprivate|internal|public|open)\b[ \t]+)?"
    r"(?:(?:final|indirect)\b[ \t]+)?"
    r"(?P<keyword>class|struct|enum|actor|extension)\b[ \t]+"
    r"(?P<name>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\b"
)


@dataclass(frozen=True, order=True)
class VisualDeclaration:
    path: str
    symbol: str
    kind: str
    line: int


def mask_comments_and_strings(source: str) -> str:
    """Replace Swift comments and strings with spaces while retaining newlines."""
    masked = list(source)
    index = 0
    length = len(source)

    def erase(start: int, end: int) -> None:
        for position in range(start, end):
            if masked[position] != "\n":
                masked[position] = " "

    while index < length:
        if source.startswith("//", index):
            end = source.find("\n", index)
            erase(index, length if end == -1 else end)
            index = length if end == -1 else end
            continue
        if source.startswith("/*", index):
            start = index
            block_depth = 1
            index += 2
            while index < length and block_depth:
                if source.startswith("/*", index):
                    block_depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    block_depth -= 1
                    index += 2
                else:
                    index += 1
            erase(start, index)
            continue

        hashes = 0
        while index + hashes < length and source[index + hashes] == "#":
            hashes += 1
        quote_index = index + hashes
        if quote_index < length and source[quote_index] == '"':
            start = index
            triple = source.startswith('\"\"\"', quote_index)
            quote_width = 3 if triple else 1
            index = quote_index + quote_width
            terminator = '"' * quote_width + ('#' * hashes)
            while index < length:
                if source[index] == "\\":
                    index += 1
                    if hashes and source.startswith("#" * hashes, index):
                        index += hashes
                    if index < length:
                        index += 1
                    continue
                if source.startswith(terminator, index):
                    index += len(terminator)
                    break
                else:
                    index += 1
            erase(start, min(index, length))
            continue
        index += 1
    return "".join(masked)


def matching_brace(source: str, opening_brace: int) -> int | None:
    depth = 0
    for index in range(opening_brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return None


def declarations_in_file(path: Path, relative_path: str) -> list[VisualDeclaration]:
    source = path.read_text(encoding="utf-8")
    masked = mask_comments_and_strings(source)
    candidates: list[tuple[int, int, int, str, str | None]] = []
    for match in DECLARATION.finditer(masked):
        name = match.group("name")
        opening_brace = masked.find("{", match.end("name"))
        if opening_brace == -1:
            continue
        header = masked[match.end("name") : opening_brace]
        inheritance = header.split(":", 1)
        closing_brace = matching_brace(masked, opening_brace)
        if closing_brace is None:
            continue
        inherited_names = (
            set(re.findall(r"\b[A-Za-z_]\w*\b", inheritance[1]))
            if len(inheritance) == 2
            else set()
        )
        concrete_kinds = [kind for kind in CONCRETE_BASE_PRECEDENCE if kind in inherited_names]
        protocol_kinds = sorted((inherited_names & VISUAL_KINDS) - set(CONCRETE_BASE_PRECEDENCE))
        kinds = concrete_kinds or protocol_kinds
        candidates.append(
            (match.start("keyword"), opening_brace, closing_brace, name, kinds[0] if kinds else None)
        )

    declarations: list[VisualDeclaration] = []
    for start, _opening, closing, name, kind in candidates:
        if kind is None:
            continue
        parents = [
            candidate
            for candidate in candidates
            if candidate[0] < start and candidate[2] > closing
        ]
        parents.sort(key=lambda candidate: candidate[0])
        symbol = ".".join([*(parent[3] for parent in parents), name])
        declarations.append(
            VisualDeclaration(
                path=relative_path,
                symbol=symbol,
                kind=kind,
                line=masked.count("\n", 0, start) + 1,
            )
        )
    return declarations


def swift_source_files(root: Path) -> list[Path]:
    declared_roots = [root / name for name in UI_SOURCE_ROOTS if (root / name).is_dir()]
    search_roots = declared_roots if declared_roots else [root]
    return sorted(
        source
        for search_root in search_roots
        for source in search_root.rglob("*.swift")
        if source.is_file()
    )


def discover_visual_declarations(root: Path) -> list[VisualDeclaration]:
    """Discover supported visual declarations beneath the declared Cadence UI roots."""
    declarations = [
        declaration
        for source in swift_source_files(root)
        for declaration in declarations_in_file(source, source.relative_to(root).as_posix())
    ]
    return sorted(declarations)


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    if not isinstance(manifest, dict) or not isinstance(manifest.get("components"), list):
        raise ValueError("Ownership manifest must contain a components array")
    return manifest


def validate_exact_object(
    value: Any,
    required_fields: frozenset[str],
    label: str,
    errors: list[str],
) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return None
    actual_fields = set(value)
    missing_fields = sorted(required_fields - actual_fields)
    unknown_fields = sorted(actual_fields - required_fields)
    if missing_fields:
        errors.append(f"{label} missing fields: {', '.join(missing_fields)}")
    if unknown_fields:
        errors.append(f"{label} unknown fields: {', '.join(unknown_fields)}")
    return value


def validate_string_list(value: Any, label: str, errors: list[str]) -> list[str] | None:
    if not isinstance(value, list) or not all(isinstance(item, str) and item.strip() for item in value):
        errors.append(f"{label} must be a string array")
        return None
    return value


def validate_manifest(source_root: Path, manifest: dict[str, Any]) -> list[str]:
    """Return deterministic validation errors for stale or incomplete inventory data."""
    errors: list[str] = []
    manifest = validate_exact_object(manifest, TOP_LEVEL_FIELDS, "manifest", errors) or {}
    if manifest.get("schemaVersion") != MANIFEST_SCHEMA_VERSION:
        errors.append(f"manifest schemaVersion must be {MANIFEST_SCHEMA_VERSION}")
    if manifest.get("sourceRoot") != MANIFEST_SOURCE_ROOT:
        errors.append(f"manifest sourceRoot must be {MANIFEST_SOURCE_ROOT}")
    if source_root.as_posix().rstrip("/").endswith(MANIFEST_SOURCE_ROOT) is False:
        errors.append(f"verification root must end with {MANIFEST_SOURCE_ROOT}")
    components = manifest.get("components")
    if not isinstance(components, list):
        return ["manifest components must be an array"]

    expected = {(item.path, item.symbol): item for item in discover_visual_declarations(source_root)}
    source_texts = {
        path: (source_root / path).read_text(encoding="utf-8")
        for path, _symbol in expected
    }
    actual: dict[tuple[str, str], dict[str, Any]] = {}
    for item in components:
        item = validate_exact_object(item, COMPONENT_FIELDS, "manifest component", errors)
        if item is None:
            continue
        key = (item.get("path"), item.get("symbol"))
        if not all(isinstance(value, str) and value and "*" not in value for value in key):
            errors.append(f"invalid manifest key: {key!r}")
            continue
        if key in actual:
            errors.append(f"duplicate manifest entry: {key[0]}::{key[1]}")
            continue
        actual[key] = item

    expected_keys = set(expected)
    actual_keys = set(actual)
    for path, symbol in sorted(expected_keys - actual_keys):
        errors.append(f"missing manifest entry: {path}::{symbol}")
    for path, symbol in sorted(actual_keys - expected_keys):
        errors.append(f"stale manifest entry: {path}::{symbol}")

    classifications = {
        "core-component",
        "media-component",
        "cadence-adapter",
        "product-shell",
        "product-only-behaviour",
    }
    reusable = {"core-component", "media-component"}
    for key, item in sorted(actual.items()):
        declaration = expected.get(key)
        if declaration is not None:
            if item.get("kind") != declaration.kind:
                errors.append(f"stale kind for {key[0]}::{key[1]}")
            if item.get("line") != declaration.line:
                errors.append(f"stale line for {key[0]}::{key[1]}")
        classification = item.get("classification")
        if classification not in classifications:
            errors.append(f"invalid classification for {key[0]}::{key[1]}: {classification!r}")
        for field in ("remainingCadenceSymbol", "wave"):
            if not isinstance(item.get(field), str) or not item[field].strip():
                errors.append(f"missing {field} for {key[0]}::{key[1]}")
        if item.get("wave") not in MIGRATION_WAVES:
            errors.append(f"invalid wave for {key[0]}::{key[1]}")
        dependencies = validate_exact_object(
            item.get("dependencies"), DEPENDENCY_FIELDS, f"dependencies for {key[0]}::{key[1]}", errors
        )
        if dependencies is not None:
            for field in DEPENDENCY_FIELDS:
                dependency_entries = dependencies.get(field)
                if not isinstance(dependency_entries, list) or not dependency_entries:
                    errors.append(f"dependencies.{field} for {key[0]}::{key[1]} must be a non-empty array")
                    continue
                for dependency in dependency_entries:
                    dependency = validate_exact_object(
                        dependency,
                        DEPENDENCY_ENTRY_FIELDS,
                        f"dependencies.{field} entry for {key[0]}::{key[1]}",
                        errors,
                    )
                    if dependency is None:
                        continue
                    if dependency.get("role") != field:
                        errors.append(f"dependencies.{field} role mismatch for {key[0]}::{key[1]}")
                    symbol = dependency.get("symbol")
                    if symbol is None:
                        continue
                    if not isinstance(symbol, str) or not symbol.strip():
                        errors.append(f"dependencies.{field} symbol missing for {key[0]}::{key[1]}")
                    elif symbol not in source_texts.get(key[0], ""):
                        errors.append(f"dependencies.{field} symbol is not source-backed for {key[0]}::{key[1]}")
        states = validate_exact_object(item.get("states"), STATE_FIELDS, f"states for {key[0]}::{key[1]}", errors)
        if states is not None:
            for field in STATE_FIELDS:
                state_values = validate_string_list(states.get(field), f"states.{field} for {key[0]}::{key[1]}", errors)
                if state_values is not None and any(value not in STATE_VALUES for value in state_values):
                    errors.append(f"unknown states.{field} value for {key[0]}::{key[1]}")
        evidence = validate_exact_object(item.get("evidence"), EVIDENCE_FIELDS, f"evidence for {key[0]}::{key[1]}", errors)
        if evidence is not None:
            if evidence.get("status") not in {"verified", "missing"}:
                errors.append(f"invalid evidence status for {key[0]}::{key[1]}")
            if not isinstance(evidence.get("detail"), str) or not evidence["detail"].strip():
                errors.append(f"missing evidence detail for {key[0]}::{key[1]}")
            references = validate_string_list(evidence.get("references"), f"evidence.references for {key[0]}::{key[1]}", errors)
            if evidence.get("status") == "verified" and not references:
                errors.append(f"verified evidence needs references for {key[0]}::{key[1]}")
            if evidence.get("status") == "missing" and references:
                errors.append(f"missing evidence cannot claim references for {key[0]}::{key[1]}")
        if classification in reusable:
            if item.get("deliveryProduct") not in {"QenTerraComponents", "QenTerraMediaComponents"}:
                errors.append(f"invalid deliveryProduct for {key[0]}::{key[1]}")
            if not isinstance(item.get("sharedSymbol"), str) or not item["sharedSymbol"].strip():
                errors.append(f"missing sharedSymbol for {key[0]}::{key[1]}")
        elif item.get("deliveryProduct") != "Cadence" or item.get("sharedSymbol") != "":
            errors.append(f"non-reusable entry must remain in Cadence: {key[0]}::{key[1]}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True, help="Cadence source root")
    parser.add_argument("--manifest", type=Path, required=True, help="Ownership manifest")
    arguments = parser.parse_args()
    errors = validate_manifest(arguments.root, load_manifest(arguments.manifest))
    if errors:
        print("UI component ownership verification failed:", file=sys.stderr)
        print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
        return 1
    print(f"Verified {len(discover_visual_declarations(arguments.root))} UI component declarations.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
