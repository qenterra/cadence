#!/usr/bin/env python3
"""Verify the Cadence UI ownership inventory against live Swift declarations."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import subprocess
import tempfile
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
CONCRETE_BASE_PRECEDENCE = ("NSTableCellView", "NSTableView", "MTKView", "NSView")
MANIFEST_SCHEMA_VERSION = 3
MANIFEST_SOURCE_ROOT = "Sources/Cadence"
TOP_LEVEL_FIELDS = frozenset(
    {"schemaVersion", "sourceRoot", "designSystemRegistry", "components", "adoptions"}
)
REGISTRY_IDENTITY_FIELDS = frozenset({"version", "sha256"})
SHARED_TARGET_FIELDS = frozenset({"componentID", "deliveryProduct", "publicSymbol"})
COMPONENT_FIELDS = frozenset(
    {
        "path",
        "symbol",
        "kind",
        "line",
        "classification",
        "resolution",
        "ownershipReason",
        "sharedTarget",
        "remainingCadenceSymbol",
        "consumers",
        "dependencies",
        "states",
        "wave",
        "evidence",
    }
)
ADOPTION_FIELDS = frozenset(
    {
        "path",
        "symbol",
        "classification",
        "resolution",
        "ownershipReason",
        "sharedTarget",
        "remainingCadenceSymbol",
        "consumers",
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
REQUIRED_SHARED_COMPOSITION = {
    ("Features/ImportMusic/ImportMusicReview.swift", "ImportMusicReview"): "BrowserRowSurface",
    ("Features/ImportMusic/ImportMusicReview.swift", "ImportMusicCandidateRow"): "BrowserRowSurface",
}
FORBIDDEN_WRAPPER_PATTERNS = {
    "background": r"\.background\b",
    "overlay": r"\.overlay\b",
    "shape": r"\b(?:RoundedRectangle|Rectangle|Circle|Capsule|Ellipse)\b",
    "fill": r"\.fill\b",
    "stroke": r"\.stroke(?:Border)?\b",
    "mask": r"\.mask\b",
    "clip": r"\.clipShape\b",
    "gradient": r"\b(?:LinearGradient|RadialGradient|AngularGradient)\b",
    "canvas": r"\bCanvas\b",
    "shader": r"\bShader\b",
    "metal": r"\b(?:MTKView|MTLRenderPipelineState|MTLCommandQueue)\b",
    "layer": r"\bCALayer\b|\baddSublayer\b",
    "AppKit hierarchy": r"\b(?:addSubview|NSButton|NSTextField|NSStackView|NSImageView)\b",
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
    """Return every Swift source below the declared Cadence source root."""
    return sorted(source for source in root.rglob("*.swift") if source.is_file())


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
    return re.search(rf"(?<![A-Za-z0-9_]){re.escape(symbol)}(?![A-Za-z0-9_])", source) is not None


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
        if members:
            data.update(f"configuration.{member}" for member in members)
        else:
            data.add("configuration")

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
    def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise ValueError(f"Duplicate JSON key: {key}")
            value[key] = item
        return value

    with path.open(encoding="utf-8") as handle:
        manifest = json.load(handle, object_pairs_hook=reject_duplicate_keys)
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


def default_repository_root(source_root: Path) -> Path:
    if source_root.name == "Cadence" and source_root.parent.name == "Sources":
        return source_root.parent.parent
    return source_root


DESIGN_SYSTEM_URL = "https://github.com/QenTerra/design-system.git"
DESIGN_SYSTEM_REGISTRY = "registry/qenterra-components.json"
PACKAGE_RESOLVED = "Cadence.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"


def design_system_revision(repository_root: Path) -> str:
    """Read the immutable source identity from the same lockfile as the app."""
    resolved = json.loads((repository_root / PACKAGE_RESOLVED).read_text(encoding="utf-8"))
    pins = [pin for pin in resolved.get("pins", []) if pin.get("identity") == "design-system"]
    if len(pins) != 1:
        raise ValueError("Package.resolved must contain exactly one Design System pin")
    pin = pins[0]
    location = pin.get("location", "").removesuffix(".git").lower()
    state = pin.get("state", {})
    revision = state.get("revision", "")
    if pin.get("kind") != "remoteSourceControl" or location != DESIGN_SYSTEM_URL.removesuffix(".git").lower():
        raise ValueError("Design System pin must use the canonical GitHub repository")
    if not isinstance(revision, str) or re.fullmatch(r"[0-9a-f]{40}", revision) is None:
        raise ValueError("Design System pin requires a full immutable Git revision")
    if state.get("branch") or not isinstance(state.get("version"), str) or re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", state["version"]) is None:
        raise ValueError("Design System pin requires an exact release version, not a branch")
    return revision


def design_system_git(checkout: Path, *arguments: str) -> bytes:
    result = subprocess.run(
        ["git", "--no-replace-objects", "-C", str(checkout), *arguments],
        check=False, capture_output=True, timeout=120,
    )
    if result.returncode:
        raise ValueError(f"Design System Git operation failed ({arguments[0]}): {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


def registry_checkout(repository_root: Path, revision: str) -> Path:
    cache_root = repository_root / ".build" / "ownership-design-system"
    checkout = cache_root / revision
    if not checkout.resolve().is_relative_to(repository_root.resolve()):
        raise ValueError("Design System registry cache must stay inside this repository")
    return checkout


def default_registry_path(repository_root: Path) -> Path:
    """Use only the locked Git blob; a mutable sibling is never a fallback."""
    revision = design_system_revision(repository_root)
    checkout = registry_checkout(repository_root, revision)
    registry = checkout / DESIGN_SYSTEM_REGISTRY
    if not registry.is_file():
        raise ValueError("Design System registry cache is missing; run this checker with --prepare-registry")
    if not registry.resolve().is_relative_to(checkout.resolve()):
        raise ValueError("Design System registry must stay inside its verified checkout")
    head = design_system_git(checkout, "rev-parse", "HEAD").decode().strip()
    if head != revision:
        raise ValueError("Design System registry checkout does not match Package.resolved")
    expected = design_system_git(checkout, "show", f"{revision}:{DESIGN_SYSTEM_REGISTRY}")
    if registry.read_bytes() != expected:
        raise ValueError("Design System registry differs from its pinned Git blob")
    return registry


def prepare_registry(repository_root: Path) -> Path:
    """Fetch a dedicated ignored checkout by commit, then verify its registry."""
    revision = design_system_revision(repository_root)
    checkout = registry_checkout(repository_root, revision)
    if checkout.exists():
        # Do not repair or overwrite unexpected cache contents silently.
        return default_registry_path(repository_root)
    checkout.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="fetch-", dir=checkout.parent) as temporary:
        staged = Path(temporary) / "checkout"
        staged.mkdir()
        design_system_git(staged, "init", "--quiet")
        design_system_git(staged, "fetch", "--quiet", "--depth=1", DESIGN_SYSTEM_URL, revision)
        design_system_git(staged, "-c", "advice.detachedHead=false", "checkout", "--quiet", "--detach", revision)
        staged.rename(checkout)
    return default_registry_path(repository_root)


def registry_targets(registry: dict[str, Any], errors: list[str]) -> set[tuple[str, str, str]]:
    components = registry.get("components")
    if not isinstance(components, list):
        errors.append("Design System registry components must be an array")
        return set()
    targets: set[tuple[str, str, str]] = set()
    for component in components:
        if not isinstance(component, dict):
            errors.append("Design System registry component must be an object")
            continue
        component_id = component.get("id")
        product = component.get("deliveryProduct")
        symbols = component.get("publicSymbols")
        if not isinstance(component_id, str) or not isinstance(product, str) or not isinstance(symbols, list):
            errors.append("Design System registry component has an invalid public identity")
            continue
        targets.update(
            (component_id, product, symbol)
            for symbol in symbols
            if isinstance(symbol, str) and symbol.strip()
        )
    return targets


def validate_shared_target(
    value: Any,
    label: str,
    targets: set[tuple[str, str, str]],
    errors: list[str],
) -> dict[str, Any] | None:
    target = validate_exact_object(value, SHARED_TARGET_FIELDS, label, errors)
    if target is None:
        return None
    triple = (
        target.get("componentID"),
        target.get("deliveryProduct"),
        target.get("publicSymbol"),
    )
    if not all(isinstance(item, str) and item.strip() for item in triple):
        errors.append(f"{label} must contain non-empty strings")
    elif triple not in targets:
        errors.append(f"{label} does not resolve in the Design System registry: {triple!r}")
    return target


def validate_ownership_reason(value: Any, label: str, errors: list[str]) -> None:
    symbol = label.rsplit("::", 1)[-1]
    if (
        not isinstance(value, str)
        or len(value.strip()) < 24
        or symbol not in value
    ):
        errors.append(f"concrete ownershipReason required for {label}")


def validate_evidence(
    value: Any,
    label: str,
    repository_root: Path,
    errors: list[str],
) -> None:
    evidence = validate_exact_object(value, EVIDENCE_FIELDS, f"evidence for {label}", errors)
    if evidence is None:
        return
    if evidence.get("status") != "verified":
        errors.append(f"incomplete Task 19 evidence for {label}")
    if not isinstance(evidence.get("detail"), str) or not evidence["detail"].strip():
        errors.append(f"missing evidence detail for {label}")
    references = validate_string_list(
        evidence.get("references"), f"evidence.references for {label}", errors
    )
    if not references:
        errors.append(f"verified evidence needs references for {label}")
        return
    for reference in references:
        reference_path = Path(reference)
        if reference_path.is_absolute() or ".." in reference_path.parts:
            errors.append(f"evidence reference must be repository-relative for {label}: {reference}")
            continue
        if reference.startswith("Sources/"):
            errors.append(f"evidence reference cannot be source-only for {label}: {reference}")
            continue
        if not (reference.startswith("Tests/") or "__Snapshots__" in reference):
            errors.append(f"evidence reference must name a test or tracked screenshot for {label}: {reference}")
        if not (repository_root / reference).is_file():
            errors.append(f"evidence reference does not exist for {label}: {reference}")


def validate_consumer(
    repository_root: Path,
    relative_path: str,
    target: dict[str, Any],
    label: str,
    errors: list[str],
) -> None:
    path = Path(relative_path)
    if path.is_absolute() or ".." in path.parts or not relative_path.startswith("Sources/Cadence/"):
        errors.append(f"consumer must be a Cadence repository-relative source for {label}: {relative_path}")
        return
    absolute_path = repository_root / path
    if not absolute_path.is_file():
        errors.append(f"consumer does not exist for {label}: {relative_path}")
        return
    source = mask_comments_and_strings(absolute_path.read_text(encoding="utf-8"))
    product = target.get("deliveryProduct", "")
    symbol = target.get("publicSymbol", "")
    if re.search(rf"(?m)^\s*import\s+{re.escape(product)}\s*$", source) is None:
        errors.append(f"consumer does not import target product for {label}: {relative_path}")
    if not has_source_reference(source, symbol):
        errors.append(f"consumer does not use target symbol for {label}: {relative_path}")


def validate_manifest(
    source_root: Path,
    manifest: dict[str, Any],
    *,
    repository_root: Path | None = None,
    registry_path: Path | None = None,
) -> list[str]:
    """Return deterministic validation errors for stale or incomplete inventory data."""
    errors: list[str] = []
    repository_root = repository_root or default_repository_root(source_root)
    try:
        registry_path = registry_path or default_registry_path(repository_root)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        return [f"Cannot verify the pinned Design System registry: {error}"]
    if not registry_path.is_file():
        errors.append(f"Design System registry does not exist: {registry_path}")
        registry: dict[str, Any] = {}
        registry_digest = ""
    else:
        try:
            registry = load_manifest(registry_path)
        except ValueError as error:
            errors.append(f"Design System registry is invalid: {error}")
            registry = {}
        registry_digest = hashlib.sha256(registry_path.read_bytes()).hexdigest()
    targets = registry_targets(registry, errors)
    manifest = validate_exact_object(manifest, TOP_LEVEL_FIELDS, "manifest", errors) or {}
    if manifest.get("schemaVersion") != MANIFEST_SCHEMA_VERSION:
        errors.append(f"manifest schemaVersion must be {MANIFEST_SCHEMA_VERSION}")
    if manifest.get("sourceRoot") != MANIFEST_SOURCE_ROOT:
        errors.append(f"manifest sourceRoot must be {MANIFEST_SOURCE_ROOT}")
    if source_root.as_posix().rstrip("/").endswith(MANIFEST_SOURCE_ROOT) is False:
        errors.append(f"verification root must end with {MANIFEST_SOURCE_ROOT}")
    registry_identity = validate_exact_object(
        manifest.get("designSystemRegistry"),
        REGISTRY_IDENTITY_FIELDS,
        "manifest designSystemRegistry",
        errors,
    )
    if registry_identity is not None:
        if registry_identity.get("version") != registry.get("version"):
            errors.append("manifest Design System registry version is stale")
        if registry_identity.get("sha256") != registry_digest:
            errors.append("manifest Design System registry sha256 is stale")
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
        resolution = item.get("resolution")
        if resolution not in {"compatibility-wrapper", "cadence-owned"}:
            errors.append(f"invalid current resolution for {key[0]}::{key[1]}: {resolution!r}")
        if classification in reusable and resolution != "compatibility-wrapper":
            errors.append(f"reusable declaration must be a compatibility-wrapper for {key[0]}::{key[1]}")
        if classification not in reusable and resolution != "cadence-owned":
            errors.append(f"Cadence declaration must use cadence-owned resolution for {key[0]}::{key[1]}")
        validate_ownership_reason(item.get("ownershipReason"), f"{key[0]}::{key[1]}", errors)
        if not isinstance(item.get("remainingCadenceSymbol"), str) or not item["remainingCadenceSymbol"].strip():
            errors.append(f"missing remainingCadenceSymbol for {key[0]}::{key[1]}")
        if not isinstance(item.get("wave"), str) or not item["wave"].strip():
            errors.append(f"missing wave for {key[0]}::{key[1]}")
        if item.get("wave") not in MIGRATION_WAVES:
            errors.append(f"invalid wave for {key[0]}::{key[1]}")
        source = declaration_sources.get(key, "")
        required_shared_symbol = REQUIRED_SHARED_COMPOSITION.get(key)
        if required_shared_symbol and not has_source_reference(source, required_shared_symbol):
            errors.append(
                f"required shared composition missing for {key[0]}::{key[1]}: "
                f"{required_shared_symbol}"
            )
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
        validate_evidence(item.get("evidence"), f"{key[0]}::{key[1]}", repository_root, errors)
        consumers = validate_string_list(item.get("consumers"), f"consumers for {key[0]}::{key[1]}", errors)
        shared_target = item.get("sharedTarget")
        if classification in reusable:
            target = validate_shared_target(
                shared_target, f"sharedTarget for {key[0]}::{key[1]}", targets, errors
            )
            if target is not None:
                qualified_symbol = f"{target.get('deliveryProduct')}.{target.get('publicSymbol')}"
                if re.search(rf"(?<![A-Za-z0-9_]){re.escape(qualified_symbol)}\s*\(", source) is None:
                    errors.append(
                        f"compatibility wrapper does not consume fully-qualified shared body for "
                        f"{key[0]}::{key[1]}: {qualified_symbol}"
                    )
                for forbidden_label, pattern in FORBIDDEN_WRAPPER_PATTERNS.items():
                    if re.search(pattern, source):
                        errors.append(
                            f"compatibility wrapper contains forbidden {forbidden_label} presentation for "
                            f"{key[0]}::{key[1]}"
                        )
        elif shared_target is not None:
            if classification != "cadence-adapter":
                errors.append(f"only a Cadence adapter may declare sharedTarget for {key[0]}::{key[1]}")
            else:
                validate_shared_target(
                    shared_target, f"sharedTarget for {key[0]}::{key[1]}", targets, errors
                )
        if consumers:
            for consumer in consumers:
                consumer_path = Path(consumer)
                if consumer_path.is_absolute() or ".." in consumer_path.parts:
                    errors.append(f"consumer must be repository-relative for {key[0]}::{key[1]}: {consumer}")
                elif not (repository_root / consumer_path).is_file():
                    errors.append(f"consumer does not exist for {key[0]}::{key[1]}: {consumer}")

    adoptions = manifest.get("adoptions")
    if not isinstance(adoptions, list):
        errors.append("manifest adoptions must be an array")
        adoptions = []
    adoption_keys: set[tuple[Any, Any]] = set()
    for item in adoptions:
        item = validate_exact_object(item, ADOPTION_FIELDS, "manifest adoption", errors)
        if item is None:
            continue
        key = (item.get("path"), item.get("symbol"))
        label = f"{key[0]}::{key[1]}"
        if not all(isinstance(value, str) and value.strip() and "*" not in value for value in key):
            errors.append(f"invalid adoption key: {key!r}")
            continue
        if key in adoption_keys:
            errors.append(f"duplicate adoption entry: {label}")
        adoption_keys.add(key)
        if any(context.declaration.symbol == item.get("symbol") for context in contexts.values()):
            errors.append(f"direct adoption former symbol is still declared: {label}")
        if item.get("classification") not in reusable:
            errors.append(f"direct adoption must retain reusable classification for {label}")
        if item.get("resolution") != "shared-direct":
            errors.append(f"direct adoption resolution must be shared-direct for {label}")
        validate_ownership_reason(item.get("ownershipReason"), label, errors)
        if item.get("remainingCadenceSymbol") is not None:
            errors.append(f"direct adoption remainingCadenceSymbol must be null for {label}")
        if item.get("wave") not in MIGRATION_WAVES:
            errors.append(f"invalid wave for {label}")
        target = validate_shared_target(item.get("sharedTarget"), f"sharedTarget for {label}", targets, errors)
        consumers = validate_string_list(item.get("consumers"), f"consumers for {label}", errors)
        if not consumers:
            errors.append(f"direct adoption needs at least one consumer for {label}")
        elif target is not None:
            for consumer in consumers:
                validate_consumer(repository_root, consumer, target, label, errors)
        validate_evidence(item.get("evidence"), label, repository_root, errors)
        old_symbol = item.get("symbol")
        new_symbol = target.get("publicSymbol") if target else None
        if isinstance(old_symbol, str) and old_symbol != new_symbol:
            for source_path in swift_source_files(source_root):
                source = mask_comments_and_strings(source_path.read_text(encoding="utf-8"))
                if has_source_reference(source, old_symbol):
                    errors.append(
                        f"direct adoption former symbol is still used: {label} in "
                        f"{source_path.relative_to(repository_root).as_posix()}"
                    )
    return sorted(set(errors))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    repository_root = Path(__file__).resolve().parents[1]
    parser.add_argument(
        "--root",
        type=Path,
        default=repository_root / MANIFEST_SOURCE_ROOT,
        help="Cadence source root",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=repository_root / "scripts" / "ui-component-ownership.json",
        help="Ownership manifest",
    )
    parser.add_argument(
        "--registry",
        type=Path,
        default=None,
        help="Design System component registry",
    )
    parser.add_argument(
        "--prepare-registry", action="store_true",
        help="Fetch and verify the Package.resolved Design System registry, then exit",
    )
    arguments = parser.parse_args()
    if arguments.prepare_registry:
        if arguments.registry is not None:
            parser.error("--prepare-registry cannot be combined with --registry")
        try:
            print(prepare_registry(repository_root))
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            print(f"Cannot prepare the pinned Design System registry: {error}", file=sys.stderr)
            return 1
        return 0
    errors = validate_manifest(
        arguments.root,
        load_manifest(arguments.manifest),
        repository_root=repository_root,
        registry_path=arguments.registry,
    )
    if errors:
        print("UI component ownership verification failed:", file=sys.stderr)
        print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
        return 1
    print(f"Verified {len(discover_visual_declarations(arguments.root))} UI component declarations.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
