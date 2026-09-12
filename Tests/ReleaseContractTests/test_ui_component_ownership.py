from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
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


class PinnedRegistryTests(unittest.TestCase):
    def fixture(self, root: Path):
        verifier = load_verifier()
        upstream = root / "upstream"
        upstream.mkdir()
        registry = upstream / "registry/qenterra-components.json"
        registry.parent.mkdir()
        registry.write_text('{"version":"2.0.0","components":[]}')
        def git(*args):
            return subprocess.check_output(["git", "-C", str(upstream), *args], stderr=subprocess.DEVNULL).decode().strip()
        git("init", "--quiet")
        git("add", ".")
        git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "Fixture")
        revision = git("rev-parse", "HEAD")
        repository = root / "cadence"
        lockfile = repository / verifier.PACKAGE_RESOLVED
        lockfile.parent.mkdir(parents=True)
        pin = {"identity": "design-system", "kind": "remoteSourceControl", "location": verifier.DESIGN_SYSTEM_URL,
               "state": {"version": "2.0.0", "revision": revision}}
        lockfile.write_text(json.dumps({"version": 3, "pins": [pin]}))
        return verifier, repository, upstream, revision, lockfile, pin

    def fetch_locally(self, verifier, repository, upstream):
        original = verifier.design_system_git
        def local_git(checkout, *arguments):
            if arguments[0] == "fetch":
                arguments = tuple(str(upstream) if item == verifier.DESIGN_SYSTEM_URL else item for item in arguments)
            return original(checkout, *arguments)
        with patch.object(verifier, "design_system_git", side_effect=local_git):
            return verifier.prepare_registry(repository)

    def test_clean_clone_prepares_pinned_registry_and_reuses_it_offline(self):
        with tempfile.TemporaryDirectory() as directory:
            verifier, repository, upstream, revision, _, _ = self.fixture(Path(directory))
            registry = self.fetch_locally(verifier, repository, upstream)
            self.assertEqual(registry.read_bytes(), (upstream / verifier.DESIGN_SYSTEM_REGISTRY).read_bytes())
            self.assertIn(revision, str(registry))
            original = verifier.design_system_git
            def offline(checkout, *arguments):
                self.assertNotIn("fetch", arguments)
                return original(checkout, *arguments)
            with patch.object(verifier, "design_system_git", side_effect=offline):
                self.assertEqual(verifier.prepare_registry(repository), registry)

    def test_missing_lock_pin_rejects_mutable_sibling_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            verifier, repository, upstream, _, lockfile, _ = self.fixture(Path(directory))
            upstream.rename(Path(directory) / "design-system")
            lockfile.write_text('{"pins": []}')
            with self.assertRaisesRegex(ValueError, "exactly one"):
                verifier.default_registry_path(repository)

    def test_pin_rejects_wrong_origin_branch_short_revision_and_duplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            verifier, repository, _, _, lockfile, pin = self.fixture(Path(directory))
            candidates = []
            for key, value in [("location", "https://example.invalid/design-system.git"), ("kind", "localSourceControl")]:
                candidate = copy.deepcopy(pin); candidate[key] = value; candidates.append([candidate])
            for key, value in [("revision", "main"), ("branch", "main"), ("version", None)]:
                candidate = copy.deepcopy(pin); candidate["state"][key] = value; candidates.append([candidate])
            candidates.append([pin, pin])
            for pins in candidates:
                with self.subTest(pins=pins):
                    lockfile.write_text(json.dumps({"pins": pins}))
                    with self.assertRaises(ValueError):
                        verifier.design_system_revision(repository)

    def test_modified_registry_and_wrong_head_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            verifier, repository, upstream, _, _, _ = self.fixture(Path(directory))
            registry = self.fetch_locally(verifier, repository, upstream)
            registry.write_text('{}')
            with self.assertRaisesRegex(ValueError, "pinned Git blob"):
                verifier.default_registry_path(repository)
            checkout = registry.parents[1]
            verifier.design_system_git(checkout, "add", ".")
            verifier.design_system_git(checkout, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "Wrong revision")
            with self.assertRaisesRegex(ValueError, "does not match Package.resolved"):
                verifier.default_registry_path(repository)

    def test_failed_fetch_does_not_poison_cache_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            verifier, repository, upstream, revision, _, _ = self.fixture(Path(directory))
            original = verifier.design_system_git
            def fail_fetch(checkout, *arguments):
                if arguments[0] == "fetch":
                    raise ValueError("simulated fetch failure")
                return original(checkout, *arguments)
            with patch.object(verifier, "design_system_git", side_effect=fail_fetch):
                with self.assertRaisesRegex(ValueError, "simulated"):
                    verifier.prepare_registry(repository)
            self.assertFalse(verifier.registry_checkout(repository, revision).exists())
            self.assertTrue(self.fetch_locally(verifier, repository, upstream).is_file())

    def test_symlinked_cache_cannot_escape_repository(self):
        with tempfile.TemporaryDirectory() as directory:
            verifier, repository, upstream, _, _, _ = self.fixture(Path(directory))
            (repository / ".build").symlink_to(upstream, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "inside this repository"):
                verifier.prepare_registry(repository)


class UIComponentOwnershipTests(unittest.TestCase):
    def test_scans_the_complete_cadence_source_root(self) -> None:
        """App-level visual declarations must not disappear when conventional UI folders exist."""
        verifier = load_verifier()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Components").mkdir()
            (root / "App").mkdir()
            (root / "Components" / "Component.swift").write_text(
                "struct ComponentSurface: View { var body: some View { EmptyView() } }",
                encoding="utf-8",
            )
            (root / "App" / "AppSurface.swift").write_text(
                "struct AppSurface: View { var body: some View { EmptyView() } }",
                encoding="utf-8",
            )

            declarations = verifier.discover_visual_declarations(root)

        self.assertEqual(
            [(item.path, item.symbol) for item in declarations],
            [
                ("App/AppSurface.swift", "AppSurface"),
                ("Components/Component.swift", "ComponentSurface"),
            ],
        )

    def test_manifest_loader_rejects_duplicate_json_keys(self) -> None:
        """Duplicate ownership keys must not silently replace reviewed values."""
        verifier = load_verifier()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text(
                '{"schemaVersion": 3, "schemaVersion": 4, "components": []}',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "Duplicate JSON key: schemaVersion"):
                verifier.load_manifest(path)

    def test_schema_v3_rejects_registry_wrapper_evidence_and_adoption_mutations(self) -> None:
        """The final ownership gate proves targets, thin bodies, evidence, and direct adoption."""
        verifier = load_verifier()
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            source_root = repository / "Sources" / "Cadence"
            tests_root = repository / "Tests" / "CadenceTests"
            source_root.mkdir(parents=True)
            tests_root.mkdir(parents=True)
            (source_root / "Wrapper.swift").write_text(
                """
                import QenTerraComponents
                struct LegacyRow: View {
                    var body: some View { QenTerraComponents.BrowserRowSurface() }
                }
                struct ProductScreen: View {
                    var body: some View { LegacyRow() }
                }
                """,
                encoding="utf-8",
            )
            (source_root / "Consumer.swift").write_text(
                "import QenTerraComponents\nlet surface = BrowserRowSurface.self\n",
                encoding="utf-8",
            )
            (tests_root / "OwnershipEvidenceTests.swift").write_text(
                "import Testing\n@Test func evidence() {}\n",
                encoding="utf-8",
            )
            registry_path = repository / "registry.json"
            registry = {
                "version": "1.0.1",
                "components": [
                    {
                        "id": "browser-row-surface",
                        "deliveryProduct": "QenTerraComponents",
                        "publicSymbols": ["BrowserRowSurface"],
                    }
                ],
            }
            registry_path.write_text(json.dumps(registry), encoding="utf-8")
            registry_digest = hashlib.sha256(registry_path.read_bytes()).hexdigest()
            evidence = {
                "status": "verified",
                "detail": "The focused ownership test constructs this exact boundary.",
                "references": ["Tests/CadenceTests/OwnershipEvidenceTests.swift"],
            }
            target = {
                "componentID": "browser-row-surface",
                "deliveryProduct": "QenTerraComponents",
                "publicSymbol": "BrowserRowSurface",
            }
            manifest = {
                "schemaVersion": 3,
                "sourceRoot": "Sources/Cadence",
                "designSystemRegistry": {"version": "1.0.1", "sha256": registry_digest},
                "adoptions": [
                    {
                        "path": "Components/RemovedRow.swift",
                        "symbol": "RemovedRow",
                        "classification": "core-component",
                        "resolution": "shared-direct",
                        "ownershipReason": "RemovedRow was replaced by the canonical browser row surface.",
                        "sharedTarget": target,
                        "remainingCadenceSymbol": None,
                        "consumers": ["Sources/Cadence/Consumer.swift"],
                        "wave": "wave-2-core",
                        "evidence": evidence,
                    }
                ],
                "components": [
                    {
                        "path": "Wrapper.swift",
                        "symbol": "LegacyRow",
                        "kind": "View",
                        "line": 3,
                        "classification": "core-component",
                        "resolution": "compatibility-wrapper",
                        "ownershipReason": "LegacyRow preserves the existing initializer while delegating drawing.",
                        "sharedTarget": target,
                        "remainingCadenceSymbol": "Cadence.LegacyRow",
                        "consumers": ["Sources/Cadence/Wrapper.swift"],
                        "dependencies": {"data": [], "actions": []},
                        "states": {
                            "appearance": ["system"],
                            "motion": ["static"],
                            "accessibility": ["native-semantics"],
                            "interaction": ["default"],
                        },
                        "wave": "wave-2-core",
                        "evidence": evidence,
                    },
                    {
                        "path": "Wrapper.swift",
                        "symbol": "ProductScreen",
                        "kind": "View",
                        "line": 6,
                        "classification": "product-shell",
                        "resolution": "cadence-owned",
                        "ownershipReason": "ProductScreen composes the Cadence navigation destination and route state.",
                        "sharedTarget": None,
                        "remainingCadenceSymbol": "Cadence.ProductScreen",
                        "consumers": [],
                        "dependencies": {"data": [], "actions": []},
                        "states": {
                            "appearance": ["system"],
                            "motion": ["static"],
                            "accessibility": ["native-semantics"],
                            "interaction": ["default"],
                        },
                        "wave": "wave-7-product",
                        "evidence": evidence,
                    },
                ],
            }

            def errors(candidate):
                return verifier.validate_manifest(
                    source_root,
                    candidate,
                    repository_root=repository,
                    registry_path=registry_path,
                )

            self.assertEqual(errors(manifest), [])
            mutations = {
                "component id": lambda value: value["components"][0]["sharedTarget"].__setitem__("componentID", "invented"),
                "delivery product": lambda value: value["components"][0]["sharedTarget"].__setitem__("deliveryProduct", "QenTerraMediaComponents"),
                "public symbol": lambda value: value["components"][0]["sharedTarget"].__setitem__("publicSymbol", "Invented"),
                "missing ownership reason": lambda value: value["components"][1].__setitem__("ownershipReason", ""),
                "generic ownership reason": lambda value: value["components"][1].__setitem__("ownershipReason", "This is product-specific Cadence behavior."),
                "missing evidence": lambda value: value["components"][1]["evidence"].__setitem__("status", "missing"),
                "source evidence": lambda value: value["components"][1]["evidence"].__setitem__("references", ["Sources/Cadence/Wrapper.swift"]),
                "no adoption consumer": lambda value: value["adoptions"][0].__setitem__("consumers", []),
            }
            for name, mutate in mutations.items():
                with self.subTest(name=name):
                    candidate = copy.deepcopy(manifest)
                    mutate(candidate)
                    self.assertTrue(errors(candidate))

            original = (source_root / "Wrapper.swift").read_text(encoding="utf-8")
            wrapper_mutations = {
                "unqualified same-name target": original.replace(
                    "QenTerraComponents.BrowserRowSurface()", "BrowserRowSurface()"
                ),
                "background": original.replace(
                    "QenTerraComponents.BrowserRowSurface()",
                    "QenTerraComponents.BrowserRowSurface().background(.red)",
                ),
                "overlay": original.replace(
                    "QenTerraComponents.BrowserRowSurface()",
                    "QenTerraComponents.BrowserRowSurface().overlay(Rectangle())",
                ),
                "appkit hierarchy": original.replace(
                    "QenTerraComponents.BrowserRowSurface()",
                    "QenTerraComponents.BrowserRowSurface().onAppear { addSubview(NSView()) }",
                ),
                "rounded rectangle": original.replace(
                    "QenTerraComponents.BrowserRowSurface()", "RoundedRectangle(cornerRadius: 8)"
                ),
                "canvas": original.replace(
                    "QenTerraComponents.BrowserRowSurface()", "Canvas { _, _ in }"
                ),
                "shader": original.replace(
                    "QenTerraComponents.BrowserRowSurface()", "Shader(function: .init(library: .default, name: \"x\"), arguments: [])"
                ),
                "metal": original.replace(
                    "QenTerraComponents.BrowserRowSurface()", "RepresentedMetalView(MTKView())"
                ),
                "layer": original.replace(
                    "QenTerraComponents.BrowserRowSurface()", "RepresentedLayer(CALayer())"
                ),
                "add sublayer": original.replace(
                    "QenTerraComponents.BrowserRowSurface()", "EmptyView().onAppear { addSublayer(layer) }"
                ),
            }
            for name, source in wrapper_mutations.items():
                with self.subTest(name=name):
                    (source_root / "Wrapper.swift").write_text(source, encoding="utf-8")
                    mutation_errors = errors(manifest)
                    if name == "unqualified same-name target":
                        self.assertTrue(
                            any("does not consume fully-qualified shared body" in error for error in mutation_errors)
                        )
                    else:
                        self.assertTrue(
                            any("forbidden" in error for error in mutation_errors)
                        )
            (source_root / "Wrapper.swift").write_text(
                original.replace(
                    "var body: some View { QenTerraComponents.BrowserRowSurface() }",
                    'var body: some View { QenTerraComponents.BrowserRowSurface() } // .overlay Canvas Shader CALayer',
                ),
                encoding="utf-8",
            )
            self.assertEqual(errors(manifest), [])

            (source_root / "Wrapper.swift").write_text(
                original.replace(
                    "var body: some View { QenTerraComponents.BrowserRowSurface() }",
                    "let target: QenTerraComponents.BrowserRowSurface\n"
                    "var body: some View { EmptyView() }",
                ),
                encoding="utf-8",
            )
            self.assertTrue(
                any("does not consume fully-qualified shared body" in error for error in errors(manifest))
            )
            (source_root / "Wrapper.swift").write_text(
                original.replace(
                    "var body: some View { QenTerraComponents.BrowserRowSurface() }",
                    "var body: some View { Helper() }\n"
                    "struct Helper: View { var body: some View { "
                    "QenTerraComponents.BrowserRowSurface() } }",
                ),
                encoding="utf-8",
            )
            self.assertTrue(
                any("does not consume fully-qualified shared body" in error for error in errors(manifest))
            )
            (source_root / "Wrapper.swift").write_text(original, encoding="utf-8")

            consumer = (source_root / "Consumer.swift").read_text(encoding="utf-8")
            (source_root / "Consumer.swift").write_text(
                consumer.replace("import QenTerraComponents\n", ""), encoding="utf-8"
            )
            self.assertTrue(errors(manifest))
            (source_root / "Consumer.swift").write_text(consumer, encoding="utf-8")

            (source_root / "Removed.swift").write_text(
                "struct RemovedRow: View { var body: some View { EmptyView() } }",
                encoding="utf-8",
            )
            adoption_errors = errors(manifest)
            self.assertTrue(any("former symbol is still declared" in error for error in adoption_errors))
            self.assertEqual(adoption_errors, sorted(set(adoption_errors)))

    def test_repository_cli_uses_fail_closed_defaults(self) -> None:
        """The documented no-argument command must validate the maintained inventory."""
        verifier = load_verifier()
        declaration_count = len(
            verifier.discover_visual_declarations(ROOT / "Sources" / "Cadence")
        )
        result = subprocess.run(
            [sys.executable, str(VERIFIER_PATH)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            f"Verified {declaration_count} UI component declarations.",
            result.stdout,
        )

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
            self.assertEqual(item["resolution"], "cadence-owned")
            self.assertTrue(item["ownershipReason"])
            self.assertTrue(item["remainingCadenceSymbol"])
            self.assertEqual(set(item["dependencies"]), {"data", "actions"})
            self.assertTrue(all(isinstance(value, list) for value in item["dependencies"].values()))
            for dependency_kind, dependencies in item["dependencies"].items():
                for dependency in dependencies:
                    self.assertEqual(set(dependency), {"symbol", "role"})
                    self.assertEqual(dependency["role"], dependency_kind)
                    self.assertIsInstance(dependency["symbol"], str)
                    self.assertTrue(dependency["symbol"])
            self.assertEqual(
                set(item["states"]),
                {"appearance", "motion", "accessibility", "interaction"},
            )
            self.assertTrue(all(item["states"].values()))
            self.assertTrue(item["wave"])
            self.assertEqual(item["evidence"]["status"], "verified")
            self.assertTrue(item["evidence"]["detail"])
            self.assertTrue(item["evidence"]["references"])
            if item["sharedTarget"] is not None:
                self.assertEqual(
                    set(item["sharedTarget"]),
                    {"componentID", "deliveryProduct", "publicSymbol"},
                )

        self.assertEqual(
            {item["symbol"] for item in manifest["adoptions"]},
            {
                "ArtworkPlaceholderView",
                "CadenceFlowLayout",
                "NativePlaybackIndicatorView",
                "TrackTableView",
                "CadenceModeBackgroundView",
                "CadenceModeGradientRenderer",
                "SettingsAboutResourceRow",
                "PlaybackProgressControl",
                "ProductionQueueDragModifier",
                "ProductionQueueDragPreview",
                "ProductionQueueInsertionIndicator",
                "ProductionQueueRowInteractionModifier",
                "CadenceModeLyricsEdgeFade",
            },
        )

    def test_cadence_adapter_target_is_registry_backed(self) -> None:
        """An adapter cannot name an invented shared target as delegated ownership."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)
        component = next(
            item for item in manifest["components"]
            if item["symbol"] == "SettingsAboutSection"
        )
        self.assertEqual(component["classification"], "cadence-adapter")
        self.assertEqual(component["sharedTarget"]["publicSymbol"], "AboutPage")

        candidate = copy.deepcopy(manifest)
        next(
            item for item in candidate["components"]
            if item["symbol"] == "SettingsAboutSection"
        )["sharedTarget"]["publicSymbol"] = "DefinitelyNotPublic"
        rejected = verifier.validate_manifest(ROOT / "Sources" / "Cadence", candidate)
        self.assertTrue(
            any("does not resolve" in error for error in rejected)
        )

    def test_manifest_requires_exact_schema_identity_and_component_shape(self) -> None:
        """A different schema/root or unknown field must not validate against Cadence sources."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)
        self.assertEqual(verifier.validate_manifest(ROOT / "Sources" / "Cadence", manifest), [])
        mutations = {
            "missing schemaVersion": lambda value: value.pop("schemaVersion"),
            "wrong schemaVersion type": lambda value: value.__setitem__("schemaVersion", "3"),
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
            "generic dependency": lambda value: value["components"][0]["dependencies"]["data"][0].__setitem__(
                "symbol", "CadenceModeHint Cadence feature presentation state"
            ),
            "unknown state": lambda value: value["components"][0]["states"].__setitem__("appearance", ["bogus"]),
            "unknown wave": lambda value: value["components"][0].__setitem__("wave", "bogus"),
            "missing evidence with reference": lambda value: value["components"][0]["evidence"].__setitem__("references", ["bogus"]),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                candidate = copy.deepcopy(manifest)
                mutate(candidate)
                self.assertTrue(verifier.validate_manifest(ROOT / "Sources" / "Cadence", candidate))

    def test_manifest_records_favorite_mutation_as_an_action(self) -> None:
        """A favorite-changing closure must not be represented as an action-free component."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)
        component = next(item for item in manifest["components"] if item["symbol"] == "PlayerBarFavoriteControl")

        self.assertIn(
            "model.setProductionPlaybackTrackFavorite",
            [entry["symbol"] for entry in component["dependencies"]["actions"]],
        )

    def test_manifest_keeps_queue_play_and_select_in_action_dependencies(self) -> None:
        """Queue interaction closures are commands, not presentation data."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)
        component = next(
            item for item in manifest["components"]
            if item["symbol"] == "ProductionPlaybackQueueRow"
        )

        data_symbols = [entry["symbol"] for entry in component["dependencies"]["data"]]
        action_symbols = [entry["symbol"] for entry in component["dependencies"]["actions"]]
        self.assertNotIn("play", data_symbols)
        self.assertNotIn("select", data_symbols)
        self.assertIn("play", action_symbols)
        self.assertIn("select", action_symbols)

    def test_manifest_records_row_button_configuration_as_data(self) -> None:
        """ButtonStyle configuration label and pressed state are source-backed visual inputs."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)
        component = next(item for item in manifest["components"] if item["symbol"] == "CadenceRowButtonStyle")

        self.assertEqual(
            ["configuration"],
            [entry["symbol"] for entry in component["dependencies"]["data"]],
        )
        self.assertEqual([], component["dependencies"]["actions"])

    def test_dependency_roles_and_empty_lists_are_checked_within_each_declaration(self) -> None:
        """A token elsewhere in a file cannot excuse false none or an action listed as data."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)
        mutations = {
            "whole-file token": lambda value: next(
                item for item in value["components"] if item["symbol"] == "CadenceRowButtonStyle"
            )["dependencies"].__setitem__(
                "data", [{"symbol": "CadenceTheme", "role": "data"}]
            ),
            "favorite action none": lambda value: next(
                item for item in value["components"] if item["symbol"] == "PlayerBarFavoriteControl"
            )["dependencies"].__setitem__("actions", []),
            "queue actions as data": lambda value: next(
                item for item in value["components"]
                if item["symbol"] == "ProductionPlaybackQueueRow"
            )["dependencies"].update(
                {"data": [{"symbol": "play", "role": "data"}], "actions": []}
            ),
            "button style data none": lambda value: next(
                item for item in value["components"] if item["symbol"] == "CadenceRowButtonStyle"
            )["dependencies"].__setitem__("data", []),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                candidate = copy.deepcopy(manifest)
                mutate(candidate)
                self.assertTrue(verifier.validate_manifest(ROOT / "Sources" / "Cadence", candidate))

    def test_dependency_source_excludes_nonvisual_nested_declarations(self) -> None:
        """A nested helper's state must not be attributed to its enclosing visual declaration."""
        verifier = load_verifier()
        fixture = '''
        struct Outer: View {
            let outerValue: Int
            final class Helper {
                let hiddenValue: Int
            }
            var body: some View { EmptyView() }
        }
        '''
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "NestedDependencyFixture.swift").write_text(fixture, encoding="utf-8")
            contexts = verifier.discover_declaration_contexts(root)
            source = verifier.declaration_source(
                contexts[("NestedDependencyFixture.swift", "Outer")], contexts
            )

        self.assertIn("outerValue", source)
        self.assertNotIn("hiddenValue", source)

    def test_dependency_lists_must_cover_every_declaration_bounded_reference(self) -> None:
        """A nonempty list cannot conceal an omitted visual input or command."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)
        mutations = {
            "omitted queue select": lambda value: next(
                item for item in value["components"]
                if item["symbol"] == "ProductionPlaybackQueueRow"
            )["dependencies"].__setitem__(
                "actions", [{"symbol": "play", "role": "actions"}]
            ),
            "omitted button style pressed state": lambda value: next(
                item for item in value["components"] if item["symbol"] == "CadenceRowButtonStyle"
            )["dependencies"].__setitem__(
                "data", [{"symbol": "configuration.label", "role": "data"}]
            ),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                candidate = copy.deepcopy(manifest)
                mutate(candidate)
                self.assertTrue(verifier.validate_manifest(ROOT / "Sources" / "Cadence", candidate))

    def test_dependency_roles_follow_consumer_contracts_not_closure_or_lifecycle_names(self) -> None:
        """Result/content closures are data; Void commands are actions; framework lifecycle values are local."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)

        catalog = next(item for item in manifest["components"] if item["symbol"] == "CatalogSortMenu")
        self.assertIn("fieldTitle", [entry["symbol"] for entry in catalog["dependencies"]["data"]])
        self.assertNotIn("fieldTitle", [entry["symbol"] for entry in catalog["dependencies"]["actions"]])

        keyboard = next(item for item in manifest["components"] if item["symbol"] == "RhythmKeyboardCapture")
        keyboard_data = [entry["symbol"] for entry in keyboard["dependencies"]["data"]]
        keyboard_actions = [entry["symbol"] for entry in keyboard["dependencies"]["actions"]]
        self.assertIn("isCadenceModeActive", keyboard_data)
        self.assertNotIn("isCadenceModeActive", keyboard_actions)
        self.assertCountEqual(
            ["onExitCadenceMode", "onKeyDown", "onKeyUp", "onReleaseAllKeys"],
            keyboard_actions,
        )
        self.assertFalse({"_", "context", "coordinator", "nsView"} & set(keyboard_data))
        self.assertNotIn("coordinator.removeMonitor", keyboard_actions)

        track_table = next(item for item in manifest["components"] if item["symbol"] == "TrackTableCore")
        track_actions = [entry["symbol"] for entry in track_table["dependencies"]["actions"]]
        self.assertCountEqual(["onReachEnd", "reorderAction"], track_actions)
        self.assertFalse(any(symbol.startswith("context.coordinator.") for symbol in track_actions))

        pane_header = next(item for item in manifest["components"] if item["symbol"] == "WorkspacePaneHeader")
        self.assertIn("trailing", [entry["symbol"] for entry in pane_header["dependencies"]["data"]])
        self.assertEqual([], pane_header["dependencies"]["actions"])

    def test_internal_compositor_storage_is_not_a_consumer_contract(self) -> None:
        """An NSView's layer maps, pools, and caches must not become data or actions."""
        verifier = load_verifier()
        manifest = verifier.load_manifest(MANIFEST_PATH)
        compositor = next(item for item in manifest["components"] if item["symbol"] == "RhythmPulseCompositorView")
        data_symbols = {entry["symbol"] for entry in compositor["dependencies"]["data"]}
        action_symbols = {entry["symbol"] for entry in compositor["dependencies"]["actions"]}
        owned = {
            "effectLayer", "state", "washLayers", "particleLayers", "washReplacementTimes",
            "washLayerPool", "particleLayerPool", "washTextureCache",
        }
        self.assertFalse(owned & data_symbols)
        self.assertFalse(any(symbol.startswith(("washLayers.", "particleLayers.", "washReplacementTimes.")) for symbol in action_symbols))

        hosting_cell = next(item for item in manifest["components"] if item["symbol"] == "TrackTableHostingCell")
        self.assertNotIn("hostState", [entry["symbol"] for entry in hosting_cell["dependencies"]["data"]])

        self.assertFalse(any(item["symbol"] == "CadenceModeGradientRenderer" for item in manifest["components"]))
        background = next(item for item in manifest["components"] if item["symbol"] == "CadenceModeBackground")
        self.assertEqual("ArtworkAccentGradientView", background["sharedTarget"]["publicSymbol"])
        background_data = {entry["symbol"] for entry in background["dependencies"]["data"]}
        self.assertEqual({"palette", "hasLiveEffects", "reduceMotion", "visualQAReduceMotionOverride"}, background_data)
        self.assertFalse({"device", "commandQueue", "snapshotPipelineState"} & background_data)

    def test_private_init_injected_closures_remain_consumer_dependencies(self) -> None:
        """Private access does not erase a callback or formatter supplied by the initializer."""
        verifier = load_verifier()
        source = '''
        final class PrivateInjectedSurface: NSView {
            private let save: () -> Void
            private let titleForValue: (Int) -> String

            init(save: @escaping () -> Void, titleForValue: @escaping (Int) -> String) {
                self.save = save
                self.titleForValue = titleForValue
                super.init(frame: .zero)
            }
        }
        '''
        data, actions = verifier.consumer_dependency_symbols(source)
        self.assertEqual({"titleForValue"}, data)
        self.assertEqual({"save"}, actions)

    def test_external_wrappers_remain_inputs_while_owned_wrappers_do_not(self) -> None:
        """Bindings, environment, and app storage are external; State-family storage is owned."""
        verifier = load_verifier()
        source = '''
        struct WrapperSurface: View {
            @Binding var selection: Bool
            @Environment(\\.colorScheme) private var colorScheme
            @AppStorage("surface.enabled") private var isEnabled = true
            @State private var isHovered = false
            @StateObject private var model = SurfaceModel()
            @FocusState private var isFocused: Bool
            @GestureState private var dragOffset = .zero
        }
        '''
        data, actions = verifier.consumer_dependency_symbols(source)
        self.assertEqual({"selection", "colorScheme", "isEnabled"}, data)
        self.assertEqual(set(), actions)

    def test_struct_defaults_and_init_assignment_are_configurable_but_class_defaults_are_owned(self) -> None:
        """Configurable SwiftUI structs retain defaults; initialized class storage stays local."""
        verifier = load_verifier()
        struct_source = '''
        struct ConfigurableSurface: View {
            var showsArtwork = true
            private let title: String

            init(title: String) {
                self.title = title
            }
        }
        '''
        class_source = '''
        final class CachedSurface: NSView {
            let cache = Cache()
            var layers: [Int: CALayer] = [:]
        }
        '''
        self.assertEqual({"showsArtwork", "title"}, verifier.data_symbols(struct_source))
        self.assertEqual(set(), verifier.data_symbols(class_source))

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
