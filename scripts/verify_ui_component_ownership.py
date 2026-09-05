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


@dataclass(frozen=True)
class DeclarationContext:
    """A visual declaration and the masked source owned by that declaration."""

    declaration: VisualDeclaration
    start: int
    end: int
    masked_source: str


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


def declaration_contexts_in_file(path: Path, relative_path: str) -> list[DeclarationContext]:
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

    contexts: list[DeclarationContext] = []
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
        contexts.append(
            DeclarationContext(
                declaration=VisualDeclaration(
                path=relative_path,
                symbol=symbol,
                kind=kind,
                line=masked.count("\n", 0, start) + 1,
                ),
                start=start,
                end=closing + 1,
                masked_source=masked,
            )
        )
    return contexts


def declarations_in_file(path: Path, relative_path: str) -> list[VisualDeclaration]:
    return [context.declaration for context in declaration_contexts_in_file(path, relative_path)]


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


def discover_declaration_contexts(root: Path) -> dict[tuple[str, str], DeclarationContext]:
    contexts = [
        context
        for source in swift_source_files(root)
        for context in declaration_contexts_in_file(source, source.relative_to(root).as_posix())
    ]
    return {(context.declaration.path, context.declaration.symbol): context for context in contexts}


def declaration_source(context: DeclarationContext, all_contexts: dict[tuple[str, str], DeclarationContext]) -> str:
    """Return the declaration signature/body, excluding nested declaration scopes."""
    source = list(context.masked_source[context.start : context.end])
    for match in DECLARATION.finditer(context.masked_source):
        start = match.start("keyword")
        opening_brace = context.masked_source.find("{", match.end("name"))
        if opening_brace == -1:
            continue
        end = matching_brace(context.masked_source, opening_brace)
        if end is None:
            continue
        if context.start < start and end < context.end:
            start -= context.start
            end = end - context.start + 1
            for index in range(start, end):
                if source[index] != "\n":
                    source[index] = " "
    return "".join(source)


def has_source_reference(source: str, symbol: str) -> bool:
    return re.search(rf"(?<![A-Za-z0-9_.]){re.escape(symbol)}(?![A-Za-z0-9_.])", source) is not None


def source_depths(source: str) -> list[int]:
    depth = 0
    depths: list[int] = []
    for character in source:
        depths.append(depth)
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
    return depths


EXTERNAL_WRAPPERS = frozenset({
    "Binding", "Environment", "EnvironmentObject", "ObservedObject", "AppStorage", "Bindable",
})
OWNED_WRAPPERS = frozenset({"State", "StateObject", "FocusState", "GestureState"})


def matching_delimiter(source: str, opening: int, opening_character: str, closing_character: str) -> int | None:
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == opening_character:
            depth += 1
        elif source[index] == closing_character:
            depth -= 1
            if depth == 0:
                return index
    return None


def initializer_property_assignments(source: str) -> tuple[set[str], set[str]]:
    """Return every initializer assignment and the subset assigned from a parameter."""
    depths = source_depths(source)
    assigned: set[str] = set()
    injected: set[str] = set()
    for match in re.finditer(r"\binit\??\s*\(", source):
        if depths[match.start()] != 1:
            continue
        opening_parenthesis = source.find("(", match.start())
        closing_parenthesis = matching_delimiter(source, opening_parenthesis, "(", ")")
        if closing_parenthesis is None:
            continue
        opening_brace = source.find("{", closing_parenthesis)
        if opening_brace == -1:
            continue
        closing_brace = matching_brace(source, opening_brace)
        if closing_brace is None:
            continue
        parameters = set(
            re.findall(
                r"(?:^|[,(])\s*(?:@\w+\s+)*(?:_\s+)?([A-Za-z_]\w*)\s*:",
                source[opening_parenthesis : closing_parenthesis + 1],
            )
        )
        for assignment in re.finditer(
            r"(?m)^\s*(?:self\.)?([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\b",
            source[opening_brace + 1 : closing_brace],
        ):
            assigned.add(assignment.group(1))
            if assignment.group(2) in parameters:
                injected.add(assignment.group(1))
    return assigned, injected


def init_injected_properties(source: str) -> set[str]:
    return initializer_property_assignments(source)[1]


def is_struct_declaration(source: str) -> bool:
    return re.search(r"(?m)^\s*(?:final\s+)?struct\b", source) is not None


def stored_consumer_inputs(source: str) -> dict[str, str]:
    """Return inputs whose ownership is proven external to the declaration."""
    depths = source_depths(source)
    initialized_in_init, injected = initializer_property_assignments(source)
    is_struct = is_struct_declaration(source)
    inputs: dict[str, str] = {}
    property_pattern = re.compile(
        r"(?m)^[ \t]*(?P<prefix>(?:@\w+(?:\([^\n)]*\))?\s+)*)"
        r"(?P<access>(?:(?:private|fileprivate|internal|public|open)\s+)?)"
        r"(?P<keyword>let|var)\s+(?P<name>[A-Za-z_]\w*)"
        r"(?:\s*:\s*(?P<type>[^\n={]+))?"
    )
    for match in property_pattern.finditer(source):
        if depths[match.start("keyword")] != 1:
            continue
        name = match.group("name")
        prefix = match.group("prefix") or ""
        access = match.group("access") or ""
        wrappers = set(re.findall(r"@(\w+)", prefix))
        if name == "body" or wrappers & OWNED_WRAPPERS:
            continue
        line_end = source.find("\n", match.end())
        line_end = len(source) if line_end == -1 else line_end
        tail = source[match.end() : line_end].lstrip()
        if tail.startswith("{"):
            continue
        initialized = tail.startswith("=")
        private = access.strip() in {"private", "fileprivate"}
        external_wrapper = bool(wrappers & EXTERNAL_WRAPPERS)
        consumer_settable_struct_default = (
            is_struct and not private and name not in initialized_in_init
        )
        uninitialized_external_storage = (
            not is_struct
            and not initialized
            and name not in initialized_in_init
            and not private
        )
        if not (
            external_wrapper
            or name in injected
            or consumer_settable_struct_default
            or uninitialized_external_storage
        ):
            continue
        inputs[name] = (match.group("type") or "").strip()
    return inputs


def closure_returns_void(type_annotation: str) -> bool:
    match = re.search(r"->\s*(?:@\w+\s+)*(?P<return>.+)$", type_annotation)
    if match is None:
        return False
    return re.sub(r"[\s?)]", "", match.group("return")) in {"Void", "("}


def consumer_dependency_symbols(source: str) -> tuple[set[str], set[str]]:
    """Infer data and commands from consumer-owned declaration inputs only."""
    inputs = stored_consumer_inputs(source)
    data: set[str] = set()
    actions: set[str] = set()
    for name, type_annotation in inputs.items():
        if "->" in type_annotation and closure_returns_void(type_annotation):
            actions.add(name)
        else:
            data.add(name)

    # SwiftUI provides these visual contracts to the component itself; lifecycle
    # parameters of representables and layout callbacks remain implementation detail.
    if re.search(r"\bfunc\s+body\s*\(\s*content\s*:\s*Content\s*\)", source):
        data.add("content")
    if re.search(r"\bfunc\s+makeBody\s*\(\s*configuration\s*:\s*Configuration\s*\)", source):
        members = sorted(set(re.findall(r"\bconfiguration\.([A-Za-z_]\w*)\b", source)))
        data.update(f"configuration.{member}" for member in members)

    actions.update(
        match.group(1)
        for match in re.finditer(
            r"\b((?:[A-Za-z_]\w*\.)+[A-Za-z_]\w*)\s*\(", source
        )
        if match.group(1).split(".", 1)[0] in data
        if match.group(1).split(".", 1)[0] not in {"context", "coordinator", "nsView"}
        if re.search(
            r"(?:^|\.)(?:set|toggle|play|select|open|close|dismiss|delete|remove|insert|update|move|reorder|perform|handle|activate|pause|stop|save|import|export|choose|show)[A-Z_]",
            match.group(1),
        )
    )
    return data, actions


def action_symbols(source: str) -> set[str]:
    return consumer_dependency_symbols(source)[1]


def data_symbols(source: str) -> set[str]:
    return consumer_dependency_symbols(source)[0]


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

    contexts = discover_declaration_contexts(source_root)
    expected = {key: context.declaration for key, context in contexts.items()}
    declaration_sources = {
        key: declaration_source(context, contexts)
        for key, context in contexts.items()
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
            source = declaration_sources.get(key, "")
            action_references = action_symbols(source)
            data_references = data_symbols(source) - action_references
            for field in DEPENDENCY_FIELDS:
                dependency_entries = dependencies.get(field)
                if not isinstance(dependency_entries, list):
                    errors.append(f"dependencies.{field} for {key[0]}::{key[1]} must be an array")
                    continue
                if not dependency_entries:
                    references = action_references if field == "actions" else data_references
                    if references:
                        errors.append(
                            f"dependencies.{field} cannot be none for {key[0]}::{key[1]}: "
                            f"{', '.join(sorted(references))}"
                        )
                recorded_symbols: set[str] = set()
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
                        errors.append(
                            f"dependencies.{field} must use [] for none for {key[0]}::{key[1]}"
                        )
                    elif not isinstance(symbol, str) or not symbol.strip():
                        errors.append(f"dependencies.{field} symbol missing for {key[0]}::{key[1]}")
                    else:
                        recorded_symbols.add(symbol)
                    if isinstance(symbol, str) and symbol.strip() and not has_source_reference(source, symbol):
                        errors.append(
                            f"dependencies.{field} symbol is not declaration-backed for {key[0]}::{key[1]}"
                        )
                    elif isinstance(symbol, str) and field == "data" and symbol in action_references:
                        errors.append(
                            f"dependencies.data symbol is an action for {key[0]}::{key[1]}: {symbol}"
                        )
                    elif isinstance(symbol, str) and field == "actions" and symbol not in action_references:
                        errors.append(
                            f"dependencies.actions symbol is not an action for {key[0]}::{key[1]}: {symbol}"
                        )
                references = action_references if field == "actions" else data_references
                missing_symbols = sorted(references - recorded_symbols)
                if missing_symbols:
                    errors.append(
                        f"dependencies.{field} is incomplete for {key[0]}::{key[1]}: "
                        f"{', '.join(missing_symbols)}"
                    )
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
