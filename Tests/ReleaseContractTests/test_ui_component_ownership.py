from __future__ import annotations

import copy
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VERIFIER_PATH = ROOT / "scripts" / "verify_ui_component_ownership.py"
MANIFEST_PATH = ROOT / "scripts" / "ui-component-ownership.json"


def load_verifier():
    spec = importlib.util.spec_from_file_location("ui_component_ownership", VERIFIER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load ownership verifier from {VERIFIER_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class UIComponentOwnershipTests(unittest.TestCase):
    def test_discovers_extension_conformances_and_qualifies_extension_nesting(self) -> None:
        """Removing extension scope handling must fail this ownership contract."""
        verifier = load_verifier()
        fixture = '''
        extension Feature: View {
            var body: some View { EmptyView() }
        }
        struct Outer {}
        extension Outer {
            private struct Nested: View {
                var body: some View { EmptyView() }
            }
        }
        '''
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "ExtensionFixture.swift").write_text(fixture, encoding="utf-8")
            declarations = verifier.discover_visual_declarations(root)

        self.assertEqual(
            [(item.symbol, item.kind) for item in declarations],
            [("Feature", "View"), ("Outer.Nested", "View")],
        )

    def test_masks_escaped_and_raw_multiline_strings_without_losing_real_line_numbers(self) -> None:
        """A string delimiter bug must not invent a component or hide a later declaration."""
        verifier = load_verifier()
        fixture = '''
        import SwiftUI

        let ordinary = "struct OrdinaryPhantom: View {}"
        let raw = #"struct RawPhantom: View {}"#
        let multiline = """
        struct MultilinePhantom: View {}
        \\"""
        still string content
        """
        let rawMultiline = #"""
        struct RawMultilinePhantom: View {}
        """#

        struct RealView: View {
            var body: some View { EmptyView() }
        }
        '''
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "StringFixture.swift").write_text(fixture, encoding="utf-8")
            declarations = verifier.discover_visual_declarations(root)

        self.assertEqual(
            [(item.symbol, item.kind, item.line) for item in declarations],
            [("RealView", "View", 15)],
        )

    def test_reports_the_declaration_keyword_line_and_prefers_a_concrete_visual_base(self) -> None:
        """A declaration after imports must retain its own line and concrete AppKit role."""
        verifier = load_verifier()
        fixture = '''
        import AppKit

        final class Hybrid: NSView, MTKViewDelegate {}
        '''
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "LineFixture.swift").write_text(fixture, encoding="utf-8")
            declarations = verifier.discover_visual_declarations(root)

        self.assertEqual(
            [(item.symbol, item.kind, item.line) for item in declarations],
            [("Hybrid", "NSView", 4)],
        )

    def test_discovers_visual_declaration_kinds_while_ignoring_comments_and_strings(self) -> None:
        """Removing a supported visual declaration kind must fail this contract."""
        verifier = load_verifier()
        fixture = '''
        // struct CommentOnly: View {}
        let sourceSnippet = "private struct StringOnly: View {}"
        private struct Outer {
            private struct NestedModifier:
                ViewModifier
            {
                func body(content: Content) -> some View { content }
            }
        }
        struct MultilineStyle:
            ButtonStyle
        {
            func makeBody(configuration: Configuration) -> some View { EmptyView() }
        }
        struct FlowLayout:
            Layout
        {
            func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { .zero }
            func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
        }
        private final class NativeView:
            NSView
        {}
        final class TrackCell: NSTableCellView {}
        struct HostView: NSViewRepresentable {
            func makeNSView(context: Context) -> NSView { NSView() }
            func updateNSView(_ nsView: NSView, context: Context) {}
        }
        final class MetalSurface: MTKView {}
        private final class Renderer: NSObject,
            MTKViewDelegate
        {}
        '''
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Fixture.swift").write_text(fixture, encoding="utf-8")
            declarations = verifier.discover_visual_declarations(root)

        self.assertEqual(
            [(item.symbol, item.kind, item.line) for item in declarations],
            [
                ("FlowLayout", "Layout", 16),
                ("HostView", "NSViewRepresentable", 26),
                ("MetalSurface", "MTKView", 30),
                ("MultilineStyle", "ButtonStyle", 11),
                ("NativeView", "NSView", 22),
                ("Outer.NestedModifier", "ViewModifier", 5),
                ("Renderer", "MTKViewDelegate", 31),
                ("TrackCell", "NSTableCellView", 25),
            ],
        )

    def test_every_visual_declaration_has_exactly_one_manifest_entry(self) -> None:
        """Removing a manifest entry or leaving a stale one must fail this contract."""
        verifier = load_verifier()
        declarations = verifier.discover_visual_declarations(ROOT / "Sources" / "Cadence")
        manifest = verifier.load_manifest(MANIFEST_PATH)
        self.assertEqual(
            {(item.path, item.symbol) for item in declarations},
            {(item["path"], item["symbol"]) for item in manifest["components"]},
        )

    def test_manifest_entries_have_complete_concrete_ownership(self) -> None:
        """Replacing an ownership decision with an empty or provisional value must fail."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)
        self.assertEqual(verifier.validate_manifest(ROOT / "Sources" / "Cadence", manifest), [])
        allowed = {
            "core-component",
            "media-component",
            "cadence-adapter",
            "product-shell",
            "product-only-behaviour",
        }
        for item in manifest["components"]:
            self.assertIn(item["classification"], allowed)
            self.assertTrue(item["remainingCadenceSymbol"])
            self.assertEqual(set(item["dependencies"]), {"data", "actions"})
            self.assertTrue(all(isinstance(value, list) for value in item["dependencies"].values()))
            for dependency_kind, dependencies in item["dependencies"].items():
                for dependency in dependencies:
                    self.assertEqual(set(dependency), {"symbol", "role"})
                    self.assertEqual(dependency["role"], dependency_kind)
                    self.assertTrue(dependency["symbol"])
            self.assertEqual(
                set(item["states"]),
                {"appearance", "motion", "accessibility", "interaction"},
            )
            self.assertTrue(all(item["states"].values()))
            self.assertTrue(item["wave"])
            self.assertIn(item["evidence"]["status"], {"verified", "missing"})
            self.assertTrue(item["evidence"]["detail"])
            self.assertIsInstance(item["evidence"]["references"], list)
            if item["classification"] in {"core-component", "media-component"}:
                self.assertIn(item["deliveryProduct"], {"QenTerraComponents", "QenTerraMediaComponents"})
                self.assertTrue(item["sharedSymbol"])
            else:
                self.assertEqual(item["deliveryProduct"], "Cadence")
                self.assertEqual(item["sharedSymbol"], "")

    def test_manifest_requires_exact_schema_identity_and_component_shape(self) -> None:
        """A different schema/root or unknown field must not validate against Cadence sources."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)
        self.assertEqual(verifier.validate_manifest(ROOT / "Sources" / "Cadence", manifest), [])
        mutations = {
            "missing schemaVersion": lambda value: value.pop("schemaVersion"),
            "wrong schemaVersion type": lambda value: value.__setitem__("schemaVersion", "2"),
            "mismatched sourceRoot": lambda value: value.__setitem__("sourceRoot", "Elsewhere"),
            "unknown top-level field": lambda value: value.__setitem__("unexpected", True),
            "unknown component field": lambda value: value["components"][0].__setitem__("unexpected", True),
            "wrong component field type": lambda value: value["components"][0].__setitem__("line", "1"),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                candidate = copy.deepcopy(manifest)
                mutate(candidate)
                self.assertTrue(verifier.validate_manifest(ROOT / "Sources" / "Cadence", candidate))

    def test_manifest_rejects_provisional_semantic_placeholders(self) -> None:
        """A fake dependency, state, wave, or evidence reference must not make migration ready."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)
        mutations = {
            "string dependency": lambda value: value["components"][0]["dependencies"].__setitem__("data", ["bogus"]),
            "unknown state": lambda value: value["components"][0]["states"].__setitem__("appearance", ["bogus"]),
            "unknown wave": lambda value: value["components"][0].__setitem__("wave", "bogus"),
            "missing evidence with reference": lambda value: value["components"][0]["evidence"].__setitem__("references", ["bogus"]),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                candidate = copy.deepcopy(manifest)
                mutate(candidate)
                self.assertTrue(verifier.validate_manifest(ROOT / "Sources" / "Cadence", candidate))

    def test_manifest_rejects_stale_and_provisional_entries(self) -> None:
        """A stale path or an unclassified component must be rejected before migration starts."""
        verifier = load_verifier()
        manifest = {
            "components": [
                {
                    "path": "Missing.swift",
                    "symbol": "Unknown",
                    "kind": "View",
                    "line": 1,
                    "classification": "unclassified",
                    "deliveryProduct": "",
                    "sharedSymbol": "",
                    "remainingCadenceSymbol": "",
                    "dependencies": [],
                    "states": [],
                    "wave": "",
                    "evidence": "",
                }
            ]
        }
        errors = verifier.validate_manifest(ROOT / "Sources" / "Cadence", manifest)
        self.assertTrue(any("Missing.swift" in error for error in errors))
        self.assertTrue(any("unclassified" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
