from __future__ import annotations

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
            self.assertTrue(item["dependencies"])
            self.assertTrue(item["states"])
            self.assertTrue(item["wave"])
            self.assertTrue(item["evidence"])
            if item["classification"] in {"core-component", "media-component"}:
                self.assertIn(item["deliveryProduct"], {"QenTerraComponents", "QenTerraMediaComponents"})
                self.assertTrue(item["sharedSymbol"])
            else:
                self.assertEqual(item["deliveryProduct"], "Cadence")
                self.assertEqual(item["sharedSymbol"], "")

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
