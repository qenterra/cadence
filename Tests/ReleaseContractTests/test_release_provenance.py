from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import plistlib
import signal
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
RELEASE_CONTRACT = ROOT / "scripts" / "release_contract.py"
RELEASE_CONTRACT_SPEC = importlib.util.spec_from_file_location(
    "cadence_release_contract_test_module", RELEASE_CONTRACT
)
assert RELEASE_CONTRACT_SPEC is not None and RELEASE_CONTRACT_SPEC.loader is not None
RELEASE_CONTRACT_MODULE = importlib.util.module_from_spec(RELEASE_CONTRACT_SPEC)
sys.modules[RELEASE_CONTRACT_SPEC.name] = RELEASE_CONTRACT_MODULE
RELEASE_CONTRACT_SPEC.loader.exec_module(RELEASE_CONTRACT_MODULE)
GATE_RECEIPTS = (
    "xcode-tests",
    "localization",
    "periphery",
    "built-product",
    "asset-catalog",
)


class ReleaseProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.tag = "v9.8.7-test.1"
        self._write_manifest()
        (self.root / "source.swift").write_text(
            "let releaseFixtureValue = 1\n", encoding="utf-8"
        )
        (self.root / ".gitignore").write_text(
            ".build/\nDeveloper/\nshims/\n", encoding="utf-8"
        )
        self.git("init", "-q")
        self.git("config", "user.name", "Cadence Tests")
        self.git("config", "user.email", "cadence-tests@example.invalid")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "fixture")
        self.git("tag", "-a", self.tag, "-m", "fixture release")
        self.sha = self.git("rev-parse", "HEAD").stdout.strip()
        self.operation_owner = subprocess.Popen(
            [sys.executable, "-I", "-B", "-c", "import time; time.sleep(300)"],
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.assertEqual(os.getpgid(self.operation_owner.pid), self.operation_owner.pid)

    def tearDown(self) -> None:
        self.stop_operation_owner()
        self.temporary_directory.cleanup()

    def stop_operation_owner(self) -> None:
        if self.operation_owner.poll() is None:
            self.operation_owner.terminate()
        self.operation_owner.wait(timeout=5)

    def test_gate_begin_accepts_exact_clean_tagged_head(self) -> None:
        result = self.run_contract("gate-begin")

        self.assertEqual(result.returncode, 0, result.stderr)
        values = self.shell_values(result.stdout)
        self.assertEqual(values["SOURCE_SHA"], self.sha)
        self.assertEqual(
            Path(values["RELEASE_ATTESTATION_PATH"]).resolve(),
            (
                self.root
                / ".build"
                / "release-attestations"
                / f"{self.sha}.json"
            ).resolve(),
        )

    def test_lightweight_manifest_tag_is_peeled_to_the_commit(self) -> None:
        self.git("tag", "-d", self.tag)
        self.git("tag", self.tag)

        result = self.run_contract("gate-begin")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.shell_values(result.stdout)["SOURCE_SHA"], self.sha)

    def test_gate_begin_rejects_manifest_tag_on_another_commit(self) -> None:
        (self.root / "later.txt").write_text("later\n", encoding="utf-8")
        self.git("add", "later.txt")
        self.git("commit", "-q", "-m", "later")

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(self.tag, result.stderr + result.stdout)
        self.assertIn("HEAD", result.stderr + result.stdout)

    def test_gate_begin_rejects_a_clean_tracked_manifest_symlink(self) -> None:
        original = (self.root / "release-contract.json").read_bytes()
        with tempfile.TemporaryDirectory() as external_directory:
            external = Path(external_directory) / "release-contract.json"
            external.write_bytes(original)
            self.git("tag", "-d", self.tag)
            (self.root / "release-contract.json").unlink()
            (self.root / "release-contract.json").symlink_to(external)
            self.git("add", "release-contract.json")
            self.git("commit", "-q", "-m", "tracked manifest symlink")
            self.git("tag", self.tag)

            result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("regular file", (result.stderr + result.stdout).lower())

    def test_gate_begin_rejects_tracked_and_untracked_dirt(self) -> None:
        manifest = self.root / "release-contract.json"
        manifest.write_text(manifest.read_text(encoding="utf-8") + "\n")
        tracked = self.run_contract("gate-begin")
        self.assertNotEqual(tracked.returncode, 0)
        self.assertIn("dirty", (tracked.stderr + tracked.stdout).lower())

        self.git("restore", "release-contract.json")
        (self.root / "untracked.txt").write_text("untracked\n", encoding="utf-8")
        untracked = self.run_contract("gate-begin")
        self.assertNotEqual(untracked.returncode, 0)
        self.assertIn("dirty", (untracked.stderr + untracked.stdout).lower())

    def test_gate_begin_rejects_assume_unchanged_tracked_bytes(self) -> None:
        self.git("update-index", "--assume-unchanged", "source.swift")
        (self.root / "source.swift").write_text(
            "let releaseFixtureValue = 999\n", encoding="utf-8"
        )
        self.assertEqual(self.git("status", "--porcelain").stdout, "")

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("assume-unchanged", (result.stderr + result.stdout).lower())

    def test_gate_begin_rejects_skip_worktree_tracked_bytes(self) -> None:
        self.git("update-index", "--skip-worktree", "source.swift")
        (self.root / "source.swift").write_text(
            "let releaseFixtureValue = 999\n", encoding="utf-8"
        )
        self.assertEqual(self.git("status", "--porcelain").stdout, "")

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("skip-worktree", (result.stderr + result.stdout).lower())

    def test_git_environment_cannot_substitute_a_clean_decoy_repository(self) -> None:
        with tempfile.TemporaryDirectory() as target_directory:
            target = Path(target_directory)
            shutil.copy2(self.root / "release-contract.json", target)
            shutil.copy2(self.root / ".gitignore", target)
            shutil.copy2(self.root / "source.swift", target)
            result = self.run_contract_at(
                target,
                "gate-begin",
                extra_env={
                    "GIT_DIR": str(self.root / ".git"),
                    "GIT_WORK_TREE": str(target),
                },
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((target / ".git").exists())
            self.assertFalse((target / ".build").exists())

    def test_git_config_environment_cannot_redirect_the_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as worktree_directory:
            redirected = Path(worktree_directory)
            shutil.copy2(self.root / "release-contract.json", redirected)
            shutil.copy2(self.root / ".gitignore", redirected)
            shutil.copy2(self.root / "source.swift", redirected)
            (self.root / "source.swift").write_text(
                "let releaseFixtureValue = 999\n", encoding="utf-8"
            )

            result = self.run_contract(
                "gate-begin",
                extra_env={
                    "GIT_CONFIG_COUNT": "1",
                    "GIT_CONFIG_KEY_0": "core.worktree",
                    "GIT_CONFIG_VALUE_0": str(redirected),
                },
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dirty", (result.stderr + result.stdout).lower())

    def test_published_beta_one_tag_is_pinned_to_its_original_commit(self) -> None:
        manifest_path = self.root / "release-contract.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["release"]["tag"] = "v0.2.0-beta.1"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.git("tag", "-d", self.tag)
        self.git("add", "release-contract.json")
        self.git("commit", "-q", "-m", "move published tag fixture")
        self.git("tag", "v0.2.0-beta.1")

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("published", (result.stderr + result.stdout).lower())

    def test_git_replace_ref_cannot_substitute_another_commit_tree(self) -> None:
        original_sha = self.sha
        (self.root / "source.swift").write_text(
            "let releaseFixtureValue = 999\n", encoding="utf-8"
        )
        self.git("add", "source.swift")
        self.git("commit", "-q", "-m", "replacement tree")
        replacement_sha = self.git("rev-parse", "HEAD").stdout.strip()
        self.git("replace", original_sha, replacement_sha)
        self.git("checkout", "-q", "--detach", original_sha)
        self.assertEqual(self.git("status", "--porcelain").stdout, "")
        self.assertIn("999", (self.root / "source.swift").read_text(encoding="utf-8"))

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("replace", (result.stderr + result.stdout).lower())

    def test_locally_ignored_swift_build_input_is_rejected(self) -> None:
        excluded = self.root / ".git" / "info" / "exclude"
        excluded.write_text("Sources/Cadence/Injected.swift\n", encoding="utf-8")
        injected = self.root / "Sources" / "Cadence" / "Injected.swift"
        injected.parent.mkdir(parents=True)
        injected.write_text("let injected = true\n", encoding="utf-8")
        self.assertEqual(self.git("status", "--porcelain").stdout, "")

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("untracked release input", (result.stderr + result.stdout).lower())

    def test_configured_global_exclude_cannot_hide_swift_build_input(self) -> None:
        excludes = self.root / ".git" / "global-release-excludes"
        excludes.write_text("Hidden.swift\n", encoding="utf-8")
        self.git("config", "core.excludesFile", str(excludes))
        injected = self.root / "Sources" / "Cadence" / "Hidden.swift"
        injected.parent.mkdir(parents=True)
        injected.write_text("let hidden = true\n", encoding="utf-8")
        self.assertEqual(self.git("status", "--porcelain").stdout, "")

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("untracked release input", (result.stderr + result.stdout).lower())

    def test_git_clean_filter_cannot_hide_raw_swift_bytes_from_tag(self) -> None:
        self.git("tag", "-d", self.tag)
        source = self.root / "Sources" / "Cadence" / "Filtered.swift"
        source.parent.mkdir(parents=True)
        source.write_text("let safe = 1\n", encoding="utf-8")
        self.git("add", "Sources/Cadence/Filtered.swift")
        self.git("commit", "-q", "-m", "tracked filtered source")
        self.git("tag", "-a", self.tag, "-m", "fixture release")
        self.sha = self.git("rev-parse", "HEAD").stdout.strip()
        (self.root / ".git" / "info" / "attributes").write_text(
            "Sources/Cadence/Filtered.swift filter=cadence-hide\n",
            encoding="utf-8",
        )
        self.git("config", "filter.cadence-hide.clean", "sed s/evil/safe/g")
        self.git("config", "filter.cadence-hide.smudge", "cat")
        self.git("config", "filter.cadence-hide.required", "true")
        source.write_text("let evil = 1\n", encoding="utf-8")
        self.assertEqual(self.git("status", "--porcelain").stdout, "")

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tagged git blob", (result.stderr + result.stdout).lower())
        self.assertFalse(
            (self.root / ".build" / "release-attestations" / f"{self.sha}.json").exists()
        )

    def test_physical_executable_mode_must_match_the_tagged_blob(self) -> None:
        self.git("tag", "-d", self.tag)
        source = self.root / "executable-fixture.sh"
        source.write_text("#!/usr/bin/env bash\n", encoding="utf-8")
        source.chmod(0o755)
        self.git("add", "executable-fixture.sh")
        self.git("commit", "-q", "-m", "tracked executable")
        self.git("tag", "-a", self.tag, "-m", "fixture release")
        self.sha = self.git("rev-parse", "HEAD").stdout.strip()
        source.chmod(0o644)

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tagged git mode", (result.stderr + result.stdout).lower())

    def test_malformed_manifest_fails_without_python_traceback(self) -> None:
        (self.root / "release-contract.json").write_text("{}\n", encoding="utf-8")

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Traceback", result.stderr + result.stdout)
        self.assertIn("manifest", (result.stderr + result.stdout).lower())

    def test_gate_begin_rejects_staged_deletion(self) -> None:
        self.git("rm", ".gitignore")

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dirty", (result.stderr + result.stdout).lower())

    def test_gate_begin_removes_only_the_captured_sha_attestation(self) -> None:
        attestation_directory = self.root / ".build" / "release-attestations"
        attestation_directory.mkdir(parents=True)
        captured = attestation_directory / f"{self.sha}.json"
        unrelated = attestation_directory / f"{'1' * 40}.json"
        captured.write_text("stale", encoding="utf-8")
        unrelated.write_text("keep", encoding="utf-8")

        result = self.run_contract("gate-begin")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(captured.exists())
        self.assertEqual(unrelated.read_text(encoding="utf-8"), "keep")

    def test_gate_complete_writes_exact_canonical_attestation(self) -> None:
        self.complete_gate()
        path = self.root / ".build" / "release-attestations" / f"{self.sha}.json"
        expected = {
            "kind": "cadence-full-gate",
            "schemaVersion": 1,
            "source": {"gitSHA": self.sha, "tag": self.tag},
            "verification": {
                "command": "scripts/verify.sh --release-attestation",
                "result": "passed",
            },
        }
        expected_bytes = (
            json.dumps(expected, sort_keys=True, separators=(",", ":")) + "\n"
        ).encode()
        self.assertEqual(path.read_bytes(), expected_bytes)

    def test_gate_complete_rejects_direct_completion_without_session(self) -> None:
        result = self.run_contract("gate-complete", "--source-sha", self.sha)

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(
            (self.root / ".build" / "release-attestations" / f"{self.sha}.json").exists()
        )

    def test_gate_complete_rechecks_source_and_leaves_no_evidence(self) -> None:
        gate_session = self.begin_gate_session()
        (self.root / "dirty.txt").write_text("dirty\n", encoding="utf-8")

        result = self.run_contract(
            "gate-complete",
            "--source-sha",
            self.sha,
            "--gate-session",
            gate_session,
            *self.gate_receipt_arguments(),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(
            (self.root / ".build" / "release-attestations" / f"{self.sha}.json").exists()
        )

    def test_gate_session_is_one_use_and_requires_every_receipt(self) -> None:
        gate_session = self.begin_gate_session()
        missing_receipt = self.run_contract(
            "gate-complete",
            "--source-sha",
            self.sha,
            "--gate-session",
            gate_session,
            *self.gate_receipt_arguments(GATE_RECEIPTS[:-1]),
        )
        self.assertNotEqual(missing_receipt.returncode, 0)

        completed = self.run_contract(
            "gate-complete",
            "--source-sha",
            self.sha,
            "--gate-session",
            gate_session,
            *self.gate_receipt_arguments(),
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)

        replay = self.run_contract(
            "gate-complete",
            "--source-sha",
            self.sha,
            "--gate-session",
            gate_session,
            *self.gate_receipt_arguments(),
        )
        self.assertNotEqual(replay.returncode, 0)
        self.assertIn("session", (replay.stderr + replay.stdout).lower())

    def test_gate_session_is_bound_to_the_begin_parent_process(self) -> None:
        gate_session = self.begin_gate_session()
        command = [
            sys.executable,
            str(RELEASE_CONTRACT),
            "gate-complete",
            "--source-sha",
            self.sha,
            "--gate-session",
            gate_session,
            *self.gate_receipt_arguments(),
            "--root",
            str(self.root),
        ]
        nested = subprocess.run(
            [
                "bash",
                "-c",
                '"$@"; release_status=$?; :; exit "$release_status"',
                "cadence-gate-parent-fixture",
                *command,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(nested.returncode, 0)
        self.assertIn("parent", (nested.stderr + nested.stdout).lower())

        accepted = self.run_contract(
            "gate-complete",
            "--source-sha",
            self.sha,
            "--gate-session",
            gate_session,
            *self.gate_receipt_arguments(),
        )
        self.assertEqual(accepted.returncode, 0, accepted.stderr)

    def test_gate_session_survives_verify_command_substitution_topology(self) -> None:
        receipt_arguments = " ".join(
            f"--gate-receipt {shlex.quote(receipt)}" for receipt in GATE_RECEIPTS
        )
        script = f"""
set -euo pipefail
gate_environment="$({shlex.quote(sys.executable)} {shlex.quote(str(RELEASE_CONTRACT))} \\
  gate-begin --gate-owner-pid \"$$\" --root {shlex.quote(str(self.root))})"
eval "$gate_environment"
{shlex.quote(sys.executable)} {shlex.quote(str(RELEASE_CONTRACT))} \\
  gate-complete --source-sha "$SOURCE_SHA" \\
  --gate-session "$RELEASE_GATE_SESSION" --gate-owner-pid "$$" \\
  {receipt_arguments} --root {shlex.quote(str(self.root))}
"""

        result = subprocess.run(
            ["bash", "-c", script],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(
            (self.root / ".build" / "release-attestations" / f"{self.sha}.json").is_file()
        )

    def test_release_preflight_requires_canonical_current_attestation(self) -> None:
        missing = self.run_contract("release-preflight")
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("attestation", (missing.stderr + missing.stdout).lower())

        self.complete_gate()
        valid = self.run_contract("release-preflight", "--expect-sha", self.sha)
        self.assertEqual(valid.returncode, 0, valid.stderr)
        values = self.shell_values(valid.stdout)
        attestation = Path(values["RELEASE_ATTESTATION_PATH"]).read_bytes()
        self.assertEqual(values["SOURCE_SHA"], self.sha)
        self.assertEqual(
            values["RELEASE_ATTESTATION_SHA256"],
            hashlib.sha256(attestation).hexdigest(),
        )

    def test_release_preflight_emits_exact_contained_artifact_paths(self) -> None:
        self.complete_gate()

        result = self.run_contract(
            "release-preflight", "--expect-sha", self.sha, "--release-mode", "local"
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        values = self.shell_values(result.stdout)
        output = self.root / ".build" / "releases" / "local" / "9.8.7-test.1"
        self.assertEqual(
            Path(values["RELEASE_OUTPUT_DIR"]).resolve(), output.resolve()
        )
        self.assertEqual(
            Path(values["RELEASE_ARCHIVE_PATH"]).resolve(),
            (
                self.root
                / ".build"
                / "Release"
                / "local"
                / "Cadence.xcarchive"
            ).resolve(),
        )
        self.assertEqual(
            Path(values["RELEASE_DMG_PATH"]).resolve(),
            (output / "Cadence-9.8.7-test.1-arm64.dmg").resolve(),
        )
        self.assertEqual(
            Path(values["RELEASE_ZIP_PATH"]).resolve(),
            (output / "Cadence-9.8.7-test.1-arm64.zip").resolve(),
        )

    def test_release_output_root_symlinks_are_rejected_before_artifacts(self) -> None:
        self.complete_gate()
        build_root = self.root / ".build"
        internal_target = self.root / ".git" / "release-output"
        (build_root / "releases").symlink_to(
            internal_target, target_is_directory=True
        )

        internal = self.run_contract(
            "release-preflight", "--expect-sha", self.sha, "--release-mode", "local"
        )

        self.assertNotEqual(internal.returncode, 0)
        self.assertIn("symlink", (internal.stderr + internal.stdout).lower())
        self.assertFalse(internal_target.exists())

    def test_external_release_output_root_symlink_is_rejected(self) -> None:
        self.complete_gate()
        with tempfile.TemporaryDirectory() as external_directory:
            external_target = Path(external_directory) / "release-output"
            (self.root / ".build" / "releases").symlink_to(
                external_target, target_is_directory=True
            )

            result = self.run_contract(
                "release-preflight",
                "--expect-sha",
                self.sha,
                "--release-mode",
                "local",
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlink", (result.stderr + result.stdout).lower())
            self.assertFalse(external_target.exists())

    def test_release_output_version_symlink_is_rejected(self) -> None:
        self.complete_gate()
        version_parent = self.root / ".build" / "releases" / "local"
        version_parent.mkdir(parents=True)
        (version_parent / "9.8.7-test.1").symlink_to(
            self.root / ".git", target_is_directory=True
        )

        result = self.run_contract(
            "release-preflight", "--expect-sha", self.sha, "--release-mode", "local"
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", (result.stderr + result.stdout).lower())

    def test_existing_artifact_symlink_is_rejected(self) -> None:
        self.complete_gate()
        output = (
            self.root / ".build" / "releases" / "local" / "9.8.7-test.1"
        )
        output.mkdir(parents=True)
        (output / "Cadence-9.8.7-test.1-arm64.dmg").symlink_to(
            self.root / ".git" / "config"
        )

        result = self.run_contract(
            "release-preflight", "--expect-sha", self.sha, "--release-mode", "local"
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", (result.stderr + result.stdout).lower())

    def test_existing_artifact_hardlinks_are_rejected(self) -> None:
        self.complete_gate()
        output = (
            self.root / ".build" / "releases" / "public" / "9.8.7-test.1"
        )
        output.mkdir(parents=True)
        names = (
            "Cadence-9.8.7-test.1-arm64.dmg",
            "Cadence-9.8.7-test.1-arm64.zip",
            "Cadence-9.8.7-test.1-SHA256SUMS.txt",
        )
        source = self.root / "source.swift"
        original = source.read_bytes()
        for name in names:
            with self.subTest(name=name):
                destination = output / name
                os.link(source, destination)

                result = self.run_contract(
                    "release-preflight",
                    "--expect-sha",
                    self.sha,
                    "--release-mode",
                    "public",
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("hard link", (result.stderr + result.stdout).lower())
                self.assertEqual(source.read_bytes(), original)
                destination.unlink()

    def test_release_operation_serializes_and_detects_path_identity_swap(self) -> None:
        self.complete_gate()
        begun = self.run_contract(
            "release-operation-begin",
            "--expect-sha",
            self.sha,
            "--release-mode",
            "local",
        )
        self.assertEqual(begun.returncode, 0, begun.stderr)
        values = self.shell_values(begun.stdout)
        operation_token = values["RELEASE_OPERATION_TOKEN"]

        competing = self.run_contract(
            "release-operation-begin",
            "--expect-sha",
            self.sha,
            "--release-mode",
            "local",
        )
        self.assertNotEqual(competing.returncode, 0)
        self.assertIn("active", (competing.stderr + competing.stdout).lower())

        archive_parent = self.root / ".build" / "Release" / "local"
        preserved_parent = self.root / ".build" / "Release" / "local-preserved"
        archive_parent.rename(preserved_parent)
        with tempfile.TemporaryDirectory() as external_directory:
            archive_parent.symlink_to(Path(external_directory), target_is_directory=True)
            checked = self.run_contract(
                "release-operation-check",
                "--release-mode",
                "local",
                "--operation-token",
                operation_token,
            )
        self.assertNotEqual(checked.returncode, 0)
        self.assertIn("identity", (checked.stderr + checked.stdout).lower())

        archive_parent.unlink()
        preserved_parent.rename(archive_parent)
        premature_end = self.run_contract(
            "release-operation-end",
            "--release-mode",
            "local",
            "--operation-token",
            operation_token,
        )
        self.assertNotEqual(premature_end.returncode, 0)
        self.assertIn(
            "live", (premature_end.stderr + premature_end.stdout).lower()
        )
        self.stop_operation_owner()
        ended = self.run_contract(
            "release-operation-end",
            "--release-mode",
            "local",
            "--operation-token",
            operation_token,
        )
        self.assertEqual(ended.returncode, 0, ended.stderr)

    def test_release_operation_recovers_only_after_recorded_owner_exits(self) -> None:
        self.complete_gate()
        owner_script = f"""
set -euo pipefail
{shlex.quote(sys.executable)} {shlex.quote(str(RELEASE_CONTRACT))} \\
  release-operation-begin --expect-sha {shlex.quote(self.sha)} \\
  --release-mode local --operation-owner-pid "$$" \\
  --root {shlex.quote(str(self.root))}
"""
        abandoned = subprocess.run(
            ["bash", "-c", owner_script],
            start_new_session=True,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(abandoned.returncode, 0, abandoned.stderr)

        recovered = self.run_contract(
            "release-operation-begin",
            "--expect-sha",
            self.sha,
            "--release-mode",
            "local",
        )

        self.assertEqual(recovered.returncode, 0, recovered.stderr)
        self.assertIn("recovered stale release operation", recovered.stderr.lower())
        token = self.shell_values(recovered.stdout)["RELEASE_OPERATION_TOKEN"]
        self.stop_operation_owner()
        ended = self.run_contract(
            "release-operation-end",
            "--release-mode",
            "local",
            "--operation-token",
            token,
        )
        self.assertEqual(ended.returncode, 0, ended.stderr)

    def test_release_operation_waits_for_every_recorded_group_member(self) -> None:
        self.complete_gate()
        child_pid_path = self.root / ".build" / "surviving-operation-child.pid"
        child_code = "import time; time.sleep(300)"
        owner_code = f"""
import os
import subprocess
import sys
from pathlib import Path

result = subprocess.run(
    {[
        sys.executable,
        str(RELEASE_CONTRACT),
        "release-operation-begin",
        "--expect-sha",
        self.sha,
        "--release-mode",
        "local",
        "--operation-owner-pid",
    ]!r} + [str(os.getpid()), "--root", {str(self.root)!r}],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
    text=True,
)
if result.returncode != 0:
    sys.stderr.write(result.stderr)
    sys.stderr.flush()
    os._exit(result.returncode)
child = subprocess.Popen(
    [sys.executable, "-I", "-B", "-c", {child_code!r}],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    close_fds=True,
)
Path({str(child_pid_path)!r}).write_text(str(child.pid), encoding="ascii")
os._exit(0)
"""
        owner = subprocess.Popen(
            [sys.executable, "-I", "-B", "-c", owner_code],
            start_new_session=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            owner_stdout, owner_stderr = owner.communicate(timeout=10)
        except BaseException:
            try:
                os.killpg(owner.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            owner.wait(timeout=5)
            raise
        self.assertEqual(owner.returncode, 0, owner_stderr + owner_stdout)
        self.assertTrue(child_pid_path.is_file())
        os.killpg(owner.pid, 0)
        operation_manifest = json.loads(
            (
                self.root
                / ".build"
                / "cadence-release-operation.lock"
                / "operation.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(operation_manifest["owner"]["pid"], owner.pid)
        self.assertEqual(operation_manifest["owner"]["processGroup"], owner.pid)

        try:
            blocked = self.run_contract(
                "release-operation-begin",
                "--expect-sha",
                self.sha,
                "--release-mode",
                "local",
            )

            self.assertNotEqual(blocked.returncode, 0, blocked.stderr + blocked.stdout)
            self.assertIn(
                "process group", (blocked.stderr + blocked.stdout).lower()
            )
        finally:
            try:
                os.killpg(owner.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                try:
                    os.killpg(owner.pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.01)
            else:
                self.fail("The abandoned operation process group did not exit.")

        recovered = self.run_contract(
            "release-operation-begin",
            "--expect-sha",
            self.sha,
            "--release-mode",
            "local",
        )
        self.assertEqual(recovered.returncode, 0, recovered.stderr)
        self.assertIn("recovered stale release operation", recovered.stderr.lower())
        token = self.shell_values(recovered.stdout)["RELEASE_OPERATION_TOKEN"]
        self.stop_operation_owner()
        ended = self.run_contract(
            "release-operation-end",
            "--release-mode",
            "local",
            "--operation-token",
            token,
        )
        self.assertEqual(ended.returncode, 0, ended.stderr)

    def test_release_operation_owner_must_lead_a_dedicated_group(self) -> None:
        self.complete_gate()
        inherited_group_process = subprocess.Popen(
            [sys.executable, "-I", "-B", "-c", "import time; time.sleep(300)"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            self.assertNotEqual(
                inherited_group_process.pid,
                os.getpgid(inherited_group_process.pid),
            )
            begun = self.run_contract(
                "release-operation-begin",
                "--expect-sha",
                self.sha,
                "--release-mode",
                "local",
                "--operation-owner-pid",
                str(inherited_group_process.pid),
            )
        finally:
            inherited_group_process.terminate()
            inherited_group_process.wait(timeout=5)

        self.assertNotEqual(begun.returncode, 0)
        self.assertIn("dedicated process group", (begun.stderr + begun.stdout).lower())

    def test_release_operation_pid_or_group_reuse_fails_closed(self) -> None:
        self.complete_gate()
        begun = self.run_contract(
            "release-operation-begin",
            "--expect-sha",
            self.sha,
            "--release-mode",
            "local",
        )
        self.assertEqual(begun.returncode, 0, begun.stderr)
        manifest_path = (
            self.root / ".build" / "cadence-release-operation.lock" / "operation.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["owner"]["startTime"] = "darwin:0:0"
        manifest_path.write_text(
            json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )

        competing = self.run_contract(
            "release-operation-begin",
            "--expect-sha",
            self.sha,
            "--release-mode",
            "local",
        )

        self.assertNotEqual(competing.returncode, 0)
        self.assertIn("reused", (competing.stderr + competing.stdout).lower())
        self.assertTrue(manifest_path.is_file())

    def test_release_operation_rejects_manifest_identity_erasure(self) -> None:
        self.complete_gate()
        begun = self.run_contract(
            "release-operation-begin",
            "--expect-sha",
            self.sha,
            "--release-mode",
            "local",
        )
        self.assertEqual(begun.returncode, 0, begun.stderr)
        operation_token = self.shell_values(begun.stdout)["RELEASE_OPERATION_TOKEN"]
        manifest_path = (
            self.root / ".build" / "cadence-release-operation.lock" / "operation.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["directories"] = []
        manifest["unexpectedOverride"] = True
        manifest_path.write_text(
            json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )

        checked = self.run_contract(
            "release-operation-check",
            "--release-mode",
            "local",
            "--operation-token",
            operation_token,
        )

        self.assertNotEqual(checked.returncode, 0)
        self.assertIn("operation manifest", (checked.stderr + checked.stdout).lower())

    def test_release_operation_hmac_rejects_schema_preserving_tamper(self) -> None:
        self.complete_gate()
        begun = self.run_contract(
            "release-operation-begin",
            "--expect-sha",
            self.sha,
            "--release-mode",
            "local",
        )
        self.assertEqual(begun.returncode, 0, begun.stderr)
        operation_token = self.shell_values(begun.stdout)["RELEASE_OPERATION_TOKEN"]
        manifest_path = (
            self.root / ".build" / "cadence-release-operation.lock" / "operation.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["directories"][0]["inode"] += 1
        manifest_path.write_text(
            json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )

        checked = self.run_contract(
            "release-operation-check",
            "--release-mode",
            "local",
            "--operation-token",
            operation_token,
        )

        self.assertNotEqual(checked.returncode, 0)
        self.assertIn("authenticate", (checked.stderr + checked.stdout).lower())

    def test_release_operation_checkpoint_revalidates_contract_bytes(self) -> None:
        self.complete_gate()
        begun = self.run_contract(
            "release-operation-begin",
            "--expect-sha",
            self.sha,
            "--release-mode",
            "local",
        )
        self.assertEqual(begun.returncode, 0, begun.stderr)
        operation_token = self.shell_values(begun.stdout)["RELEASE_OPERATION_TOKEN"]
        contract_path = self.root / "release-contract.json"
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
        contract["product"]["humanReleaseName"] = "Changed during packaging"
        contract_path.write_text(json.dumps(contract), encoding="utf-8")

        checked = self.run_contract(
            "release-operation-check",
            "--release-mode",
            "local",
            "--operation-token",
            operation_token,
        )

        self.assertNotEqual(checked.returncode, 0)
        self.assertIn("contract changed", (checked.stderr + checked.stdout).lower())
        self.git("restore", "release-contract.json")
        self.stop_operation_owner()
        ended = self.run_contract(
            "release-operation-end",
            "--release-mode",
            "local",
            "--operation-token",
            operation_token,
        )
        self.assertEqual(ended.returncode, 0, ended.stderr)

    def test_malformed_operation_lock_fails_closed_without_auto_recovery(self) -> None:
        self.complete_gate()
        lock = self.root / ".build" / "cadence-release-operation.lock"
        lock.mkdir()
        (lock / "operation.json").write_text("{}\n", encoding="utf-8")

        begun = self.run_contract(
            "release-operation-begin",
            "--expect-sha",
            self.sha,
            "--release-mode",
            "local",
        )

        self.assertNotEqual(begun.returncode, 0)
        self.assertIn("malformed", (begun.stderr + begun.stdout).lower())
        self.assertIn("explicit", (begun.stderr + begun.stdout).lower())
        self.assertTrue(lock.is_dir())
        self.assertEqual((lock / "operation.json").read_text(encoding="utf-8"), "{}\n")

    def test_checksum_writer_replaces_late_hardlink_without_mutating_source(self) -> None:
        self.complete_gate()
        begun = self.run_contract(
            "release-operation-begin",
            "--expect-sha",
            self.sha,
            "--release-mode",
            "public",
        )
        self.assertEqual(begun.returncode, 0, begun.stderr)
        values = self.shell_values(begun.stdout)
        operation_token = values["RELEASE_OPERATION_TOKEN"]
        dmg_path = Path(values["RELEASE_DMG_PATH"])
        zip_path = Path(values["RELEASE_ZIP_PATH"])
        checksum_path = Path(values["RELEASE_CHECKSUMS_PATH"])
        dmg_path.write_bytes(b"dmg fixture\n")
        zip_path.write_bytes(b"zip fixture\n")
        protected = self.root / ".build" / "protected-checksum-alias.bin"
        protected.write_bytes(b"protected fixture\n")
        protected_bytes = protected.read_bytes()
        os.link(protected, checksum_path)

        written = self.run_contract(
            "release-checksums-write",
            "--release-mode",
            "public",
            "--operation-token",
            operation_token,
        )

        self.assertEqual(written.returncode, 0, written.stderr)
        self.assertEqual(protected.read_bytes(), protected_bytes)
        self.assertEqual(checksum_path.stat().st_nlink, 1)
        self.assertEqual(
            checksum_path.read_text(encoding="ascii"),
            f"{hashlib.sha256(dmg_path.read_bytes()).hexdigest()}  {dmg_path.name}\n"
            f"{hashlib.sha256(zip_path.read_bytes()).hexdigest()}  {zip_path.name}\n",
        )

        self.stop_operation_owner()
        ended = self.run_contract(
            "release-operation-end",
            "--release-mode",
            "public",
            "--operation-token",
            operation_token,
        )
        self.assertEqual(ended.returncode, 0, ended.stderr)

    def test_release_preflight_rejects_duplicate_or_noncanonical_json(self) -> None:
        path = self.root / ".build" / "release-attestations" / f"{self.sha}.json"
        path.parent.mkdir(parents=True)
        path.write_text(
            '{"kind":"cadence-full-gate","kind":"cadence-full-gate"}\n',
            encoding="utf-8",
        )
        duplicate = self.run_contract("release-preflight")
        self.assertNotEqual(duplicate.returncode, 0)

        self.complete_gate()
        canonical = json.loads(path.read_text(encoding="utf-8"))
        path.write_text(json.dumps(canonical, indent=2) + "\n", encoding="utf-8")
        noncanonical = self.run_contract("release-preflight")
        self.assertNotEqual(noncanonical.returncode, 0)
        self.assertIn("canonical", (noncanonical.stderr + noncanonical.stdout).lower())

    def test_release_preflight_rejects_unknown_schema_keys(self) -> None:
        self.complete_gate()
        path = self.root / ".build" / "release-attestations" / f"{self.sha}.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["operatorOverride"] = True
        path.write_text(
            json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )

        result = self.run_contract("release-preflight")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("schema", (result.stderr + result.stdout).lower())

    def test_archive_stamp_and_check_bind_signed_plist_and_exact_bytes(self) -> None:
        attestation = self.complete_gate()
        archive = self.make_archive(attestation)

        stamped = self.run_contract(
            "archive-stamp", "--archive", str(archive), "--source-sha", self.sha
        )
        checked = self.run_contract(
            "archive-check", "--archive", str(archive), "--source-sha", self.sha
        )

        self.assertEqual(stamped.returncode, 0, stamped.stderr)
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertEqual(
            (archive / "CadenceReleaseAttestation.json").read_bytes(),
            attestation,
        )

    def test_archive_check_rejects_same_version_archive_from_another_sha(self) -> None:
        attestation = self.complete_gate()
        archive = self.make_archive(attestation, source_sha="2" * 40)

        result = self.run_contract(
            "archive-check", "--archive", str(archive), "--source-sha", self.sha
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source SHA", result.stderr + result.stdout)

    def test_archive_check_rejects_sidecar_tampering(self) -> None:
        attestation = self.complete_gate()
        archive = self.make_archive(attestation)
        self.assertEqual(
            self.run_contract(
                "archive-stamp", "--archive", str(archive), "--source-sha", self.sha
            ).returncode,
            0,
        )
        (archive / "CadenceReleaseAttestation.json").write_bytes(attestation + b" ")

        result = self.run_contract(
            "archive-check", "--archive", str(archive), "--source-sha", self.sha
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("attestation", (result.stderr + result.stdout).lower())

    def test_archive_check_rejects_missing_legacy_provenance(self) -> None:
        attestation = self.complete_gate()
        archive = self.make_archive(attestation)

        result = self.run_contract(
            "archive-check", "--archive", str(archive), "--source-sha", self.sha
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing", (result.stderr + result.stdout).lower())

    def test_archive_stamp_rejects_wrong_tag_and_gate_digest(self) -> None:
        attestation = self.complete_gate()
        archive = self.make_archive(attestation)
        info_path = (
            archive
            / "Products"
            / "Applications"
            / "Cadence.app"
            / "Contents"
            / "Info.plist"
        )
        with info_path.open("rb") as handle:
            info = plistlib.load(handle)
        info["CadenceReleaseTag"] = "v0.0.0-wrong"
        with info_path.open("wb") as handle:
            plistlib.dump(info, handle)
        wrong_tag = self.run_contract(
            "archive-stamp", "--archive", str(archive), "--source-sha", self.sha
        )
        self.assertNotEqual(wrong_tag.returncode, 0)

        info["CadenceReleaseTag"] = self.tag
        info["CadenceFullGateAttestationSHA256"] = "0" * 64
        with info_path.open("wb") as handle:
            plistlib.dump(info, handle)
        wrong_digest = self.run_contract(
            "archive-stamp", "--archive", str(archive), "--source-sha", self.sha
        )
        self.assertNotEqual(wrong_digest.returncode, 0)

    def test_archive_path_with_unicode_and_spaces_is_handled_as_one_path(self) -> None:
        attestation = self.complete_gate()
        archive = (
            self.root
            / ".build"
            / "Release"
            / "local"
            / "Cadence café fixture.xcarchive"
        )
        self.make_archive(attestation, archive=archive)

        stamped = self.run_contract(
            "archive-stamp", "--archive", str(archive), "--source-sha", self.sha
        )
        checked = self.run_contract(
            "archive-check", "--archive", str(archive), "--source-sha", self.sha
        )

        self.assertEqual(stamped.returncode, 0, stamped.stderr)
        self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_archive_path_symlink_escape_is_rejected(self) -> None:
        attestation = self.complete_gate()
        release_root = self.root / ".build" / "Release" / "local"
        release_root.mkdir(parents=True)
        with tempfile.TemporaryDirectory() as external_directory:
            external = Path(external_directory) / "Cadence.xcarchive"
            self.make_archive(attestation, archive=external)
            redirected = release_root / "Cadence.xcarchive"
            redirected.symlink_to(external, target_is_directory=True)

            result = self.run_contract(
                "archive-check",
                "--archive",
                str(redirected),
                "--source-sha",
                self.sha,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", (result.stderr + result.stdout).lower())

    def test_release_root_symlink_escape_is_rejected(self) -> None:
        attestation = self.complete_gate()
        build_root = self.root / ".build"
        build_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory() as external_directory:
            external_release = Path(external_directory) / "Release"
            archive = external_release / "local" / "Cadence.xcarchive"
            self.make_archive(attestation, archive=archive)
            (build_root / "Release").symlink_to(
                external_release, target_is_directory=True
            )

            result = self.run_contract(
                "archive-check", "--archive", str(archive), "--source-sha", self.sha
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", (result.stderr + result.stdout).lower())

    def test_attestation_root_symlink_into_git_is_rejected(self) -> None:
        build_root = self.root / ".build"
        build_root.mkdir()
        redirected = self.root / ".git" / "provenance"
        (build_root / "release-attestations").symlink_to(
            redirected, target_is_directory=True
        )

        result = self.run_contract("gate-begin")

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(redirected.exists())

    def test_release_root_symlink_into_git_is_rejected(self) -> None:
        attestation = self.complete_gate()
        build_root = self.root / ".build"
        release_target = self.root / ".git" / "release"
        archive = release_target / "local" / "Cadence.xcarchive"
        self.make_archive(attestation, archive=archive)
        (archive / "CadenceReleaseAttestation.json").write_bytes(attestation)
        (build_root / "Release").symlink_to(
            release_target, target_is_directory=True
        )

        result = self.run_contract(
            "archive-check",
            "--archive",
            str(build_root / "Release" / "local" / "Cadence.xcarchive"),
            "--source-sha",
            self.sha,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", (result.stderr + result.stdout).lower())

    def test_manifest_artifact_names_and_version_are_safe_components(self) -> None:
        manifest_path = self.root / "release-contract.json"
        attacks = (
            (("release", "version"), "../../escaped"),
            (("artifacts", "installer"), "../../escaped.dmg"),
            (("artifacts", "update"), "/private/tmp/escaped.zip"),
            (("artifacts", "checksums"), "nested/escaped.txt"),
        )
        original = json.loads(manifest_path.read_text(encoding="utf-8"))
        for keys, attack in attacks:
            with self.subTest(field=".".join(keys), value=attack):
                manifest = json.loads(json.dumps(original))
                manifest[keys[0]][keys[1]] = attack
                manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

                result = self.run_contract("env")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("component", (result.stderr + result.stdout).lower())
        manifest_path.write_text(json.dumps(original), encoding="utf-8")

    def test_archive_info_plist_symlink_escape_is_rejected(self) -> None:
        attestation = self.complete_gate()
        archive = self.make_archive(attestation)
        info_path = (
            archive
            / "Products"
            / "Applications"
            / "Cadence.app"
            / "Contents"
            / "Info.plist"
        )
        escaped = self.root / ".build" / "escaped-info.plist"
        escaped.write_bytes(info_path.read_bytes())
        info_path.unlink()
        info_path.symlink_to(escaped)

        result = self.run_contract(
            "archive-stamp", "--archive", str(archive), "--source-sha", self.sha
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", (result.stderr + result.stdout).lower())

    def complete_gate(self) -> bytes:
        gate_session = self.begin_gate_session()
        result = self.run_contract(
            "gate-complete",
            "--source-sha",
            self.sha,
            "--gate-session",
            gate_session,
            *self.gate_receipt_arguments(),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return (
            self.root / ".build" / "release-attestations" / f"{self.sha}.json"
        ).read_bytes()

    def begin_gate_session(self) -> str:
        result = self.run_contract("gate-begin")
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.shell_values(result.stdout)["RELEASE_GATE_SESSION"]

    @staticmethod
    def gate_receipt_arguments(
        receipts: tuple[str, ...] = GATE_RECEIPTS,
    ) -> tuple[str, ...]:
        return tuple(
            argument
            for receipt in receipts
            for argument in ("--gate-receipt", receipt)
        )

    def make_archive(
        self,
        attestation: bytes,
        *,
        source_sha: str | None = None,
        archive: Path | None = None,
    ) -> Path:
        archive = archive or (
            self.root / ".build" / "Release" / "local" / "Cadence.xcarchive"
        )
        contents = archive / "Products" / "Applications" / "Cadence.app" / "Contents"
        contents.mkdir(parents=True)
        info = {
            "CFBundleIdentifier": "com.qenterra.cadence",
            "CFBundleShortVersionString": "9.8.7",
            "CFBundleVersion": "1",
            "CadenceSourceGitSHA": source_sha or self.sha,
            "CadenceReleaseTag": self.tag,
            "CadenceFullGateAttestationSHA256": hashlib.sha256(attestation).hexdigest(),
        }
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump(info, handle)
        return archive

    def run_contract(
        self,
        command: str,
        *arguments: str,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return self.run_contract_at(
            self.root, command, *arguments, extra_env=extra_env
        )

    def run_contract_at(
        self,
        root: Path,
        command: str,
        *arguments: str,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        operation_commands = {
            "release-operation-begin",
            "release-operation-check",
            "release-checksums-write",
        }
        operation_arguments = list(arguments)
        if (
            command in operation_commands
            and "--operation-owner-pid" not in operation_arguments
        ):
            operation_arguments.extend(
                ["--operation-owner-pid", str(self.operation_owner.pid)]
            )
        return subprocess.run(
            [
                sys.executable,
                str(RELEASE_CONTRACT),
                command,
                *operation_arguments,
                "--root",
                str(root),
            ],
            check=False,
            capture_output=True,
            text=True,
            env={**os.environ, **(extra_env or {})},
        )

    def git(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", "-C", str(self.root), *arguments],
            check=True,
            capture_output=True,
            text=True,
            env={**os.environ, "LC_ALL": "C"},
        )

    @staticmethod
    def shell_values(output: str) -> dict[str, str]:
        values: dict[str, str] = {}
        for line in output.splitlines():
            if "=" not in line:
                continue
            key, encoded = line.split("=", 1)
            parsed = shlex.split(encoded)
            if len(parsed) == 1:
                values[key] = parsed[0]
        return values

    def _write_manifest(self) -> None:
        manifest = {
            "schemaVersion": 1,
            "product": {
                "name": "Cadence",
                "artifactStem": "Cadence",
                "bundleIdentifier": "com.qenterra.cadence",
                "humanReleaseName": "Cadence 9.8.7 Test 1 (1)",
            },
            "release": {
                "marketingVersion": "9.8.7",
                "build": 1,
                "channel": "test",
                "iteration": 1,
                "version": "9.8.7-test.1",
                "tag": self.tag,
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
            "artifacts": {
                "installer": "Cadence-9.8.7-test.1-arm64.dmg",
                "update": "Cadence-9.8.7-test.1-arm64.zip",
                "checksums": "Cadence-9.8.7-test.1-SHA256SUMS.txt",
            },
        }
        (self.root / "release-contract.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )


class ReleaseProvenanceScriptContractTests(unittest.TestCase):
    def test_supervisor_permission_probe_still_proves_group_exists(self) -> None:
        with mock.patch.object(
            RELEASE_CONTRACT_MODULE.os,
            "killpg",
            side_effect=PermissionError,
        ):
            self.assertTrue(
                RELEASE_CONTRACT_MODULE._supervised_process_group_exists(12345)
            )

    def test_dmg_image_tools_are_pinned_and_selected_before_running_tests(self) -> None:
        requirements = (ROOT / "requirements-dev.txt").read_text(
            encoding="utf-8"
        )
        setup = (ROOT / "scripts" / "prepare_python_tools.sh").read_text(
            encoding="utf-8"
        )
        verify = (ROOT / "scripts" / "verify.sh").read_text(encoding="utf-8")

        self.assertIn("Pillow==12.3.0", requirements)
        self.assertIn("-m venv", setup)
        self.assertIn("requirements-dev.txt", setup)
        self.assertIn(".build/python-tools/bin/python", verify)
        self.assertIn("import PIL", verify)
        self.assertIn('DEVELOPER_DIR="$developer_dir" swiftlint lint', verify)
        self.assertLess(
            verify.index("import PIL"),
            verify.index("test_dmg_background.py"),
        )

    def test_verify_has_explicit_full_gate_attestation_and_honest_partial_result(self) -> None:
        script = (ROOT / "scripts" / "verify.sh").read_text(encoding="utf-8")

        self.assertIn("--release-attestation", script)
        self.assertIn("gate-begin", script)
        self.assertIn("gate-complete", script)
        self.assertIn("--gate-session", script)
        for receipt in GATE_RECEIPTS:
            self.assertIn(f"--gate-receipt {receipt}", script)
        self.assertLess(script.index("gate-begin"), script.index("xcodegen generate"))
        self.assertGreater(script.index("gate-complete"), script.index("assetutil"))
        self.assertIn("PARTIAL HOSTED CHECKS PASSED", script)
        self.assertIn("Xcode build/tests", script)
        self.assertIn("NOT RUN", script)
        self.assertIn("not the full release gate", script)
        self.assertIn("no release attestation", script)

    def test_prepare_release_checks_source_and_archive_before_release_side_effects(self) -> None:
        script = (ROOT / "scripts" / "prepare_release.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("release-preflight", script)
        self.assertIn("archive-stamp", script)
        self.assertIn("archive-check", script)
        self.assertIn("CADENCE_SOURCE_GIT_SHA", script)
        self.assertIn("CADENCE_RELEASE_TAG", script)
        self.assertIn("CADENCE_FULL_GATE_ATTESTATION_SHA256", script)
        self.assertLess(script.index("release-preflight"), script.index("xcodegen generate"))
        self.assertLess(script.index("archive-check"), script.index("codesign --verify"))
        self.assertLess(script.index("archive-check"), script.index("notarytool submit"))
        self.assertLess(script.index("archive-check"), script.index("appcast_staging"))

    def test_hosted_ci_names_partial_gate_and_never_requests_attestation(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("partial", workflow.lower())
        self.assertIn("Xcode 27 gate unavailable", workflow)
        self.assertIn('CADENCE_SKIP_XCODEBUILD: "1"', workflow)
        self.assertNotIn("--release-attestation", workflow)

    def test_project_declares_signed_provenance_keys_with_unattested_defaults(self) -> None:
        project = (ROOT / "project.yml").read_text(encoding="utf-8")
        info = (ROOT / "Sources" / "Cadence" / "Resources" / "Info.plist").read_text(
            encoding="utf-8"
        )

        for key in (
            "CADENCE_SOURCE_GIT_SHA",
            "CADENCE_RELEASE_TAG",
            "CADENCE_FULL_GATE_ATTESTATION_SHA256",
        ):
            self.assertIn(key, project)
        for key in (
            "CadenceSourceGitSHA",
            "CadenceReleaseTag",
            "CadenceFullGateAttestationSHA256",
        ):
            self.assertIn(key, project)
            self.assertIn(key, info)
        self.assertIn("UNATTESTED", project)
        self.assertIn("UNTAGGED", project)


class ReleasePreparationOrderingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.scripts = self.root / "scripts"
        self.scripts.mkdir()
        shutil.copy2(RELEASE_CONTRACT, self.scripts / "release_contract.py")
        shutil.copy2(ROOT / "scripts" / "prepare_release.sh", self.scripts)
        shutil.copy2(ROOT / "scripts" / "verify.sh", self.scripts)
        shutil.copy2(ROOT / "scripts" / "swiftlint_debt_gate.py", self.scripts)
        shutil.copy2(
            ROOT / "scripts" / "swiftlint-warning-baseline.json",
            self.scripts,
        )
        release_directory = self.root / "release"
        release_directory.mkdir()
        self.notes = release_directory / "release-notes-9.8.7-test.1.md"
        self.notes.write_text("Fixture notes\n", encoding="utf-8")
        self.tag = "v9.8.7-test.1"
        self._write_release_surfaces()
        self.git("init", "-q")
        self.git("config", "user.name", "Cadence Tests")
        self.git("config", "user.email", "cadence-tests@example.invalid")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "fixture")
        self.git("tag", "-a", self.tag, "-m", "fixture release")
        self.sha = self.git("rev-parse", "HEAD").stdout.strip()
        self.shim_directory = self.root / "shims"
        self.shim_directory.mkdir()
        self.trace = self.root / ".build" / "command-trace.txt"
        self.developer_directory = self.root / "Developer"
        self.developer_directory.mkdir()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_dirty_source_fails_before_any_release_tool(self) -> None:
        self.install_trace_shims()
        (self.root / "dirty.txt").write_text("dirty\n", encoding="utf-8")

        result = self.run_prepare()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dirty", (result.stderr + result.stdout).lower())
        self.assertEqual(self.trace_lines(), [])

    def test_missing_full_gate_evidence_fails_before_any_release_tool(self) -> None:
        self.install_trace_shims()

        result = self.run_prepare()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("attestation", (result.stderr + result.stdout).lower())
        self.assertEqual(self.trace_lines(), [])

    def test_default_release_notes_follow_the_contract_public_version(self) -> None:
        self.complete_gate()
        self.make_reused_archive(source_sha=self.sha, include_attestation=False)
        self.install_trace_shims(prepare_success=True)

        result = self.run_prepare(use_default_notes=True)

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("Prepared local validation artifact", result.stdout)

    def test_caller_relative_release_notes_are_resolved_before_project_cd(self) -> None:
        self.complete_gate()
        with tempfile.TemporaryDirectory() as caller_directory_name:
            caller_directory = Path(caller_directory_name)
            relative_notes = os.path.relpath(self.notes, caller_directory)

            result = subprocess.run(
                [
                    sys.executable,
                    str(self.scripts / "release_contract.py"),
                    "release-preflight",
                    "--release-mode",
                    "local",
                    "--release-notes",
                    relative_notes,
                    "--root",
                    str(self.root),
                ],
                cwd=caller_directory,
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        values = ReleaseProvenanceTests.shell_values(result.stdout)
        self.assertEqual(
            Path(values["RELEASE_NOTES_PATH"]).resolve(), self.notes.resolve()
        )

    def test_release_notes_outside_release_root_fail_before_tools(self) -> None:
        self.complete_gate()
        self.install_trace_shims()
        with tempfile.TemporaryDirectory() as outside_directory_name:
            outside_notes = Path(outside_directory_name) / "outside-notes.md"
            outside_notes.write_text("Outside notes\n", encoding="utf-8")

            result = self.run_prepare(release_notes=outside_notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside", (result.stderr + result.stdout).lower())
        self.assertEqual(self.trace_lines(), [])

    def test_untracked_release_notes_fail_before_tools(self) -> None:
        self.complete_gate()
        self.install_trace_shims()
        untracked_notes = self.root / "release" / "untracked-notes.md"
        untracked_notes.write_text("Untracked notes\n", encoding="utf-8")

        result = self.run_prepare(release_notes=untracked_notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("untracked", (result.stderr + result.stdout).lower())
        self.assertEqual(self.trace_lines(), [])

    def test_generated_project_diff_fails_before_xcodebuild(self) -> None:
        self.complete_gate()
        self.install_trace_shims(xcodegen_mutates_project=True)

        result = self.run_prepare()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dirty", (result.stderr + result.stdout).lower())
        self.assertEqual(self.trace_lines(), ["xcodegen"])

    def test_dependency_resolution_drift_fails_before_archive(self) -> None:
        self.complete_gate()
        self.install_trace_shims(xcodebuild_resolve_mutates_package=True)

        result = self.run_prepare()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dirty", (result.stderr + result.stdout).lower())
        self.assertEqual(self.trace_lines(), ["xcodegen", "xcodebuild-resolve"])

    def test_reused_same_version_wrong_sha_archive_fails_before_codesign(self) -> None:
        self.complete_gate()
        self.install_trace_shims()
        self.make_reused_archive(source_sha="3" * 40, include_attestation=True)

        result = self.run_prepare(reuse_archive=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source SHA", result.stderr + result.stdout)
        self.assertEqual(self.trace_lines(), [])

    def test_reused_legacy_archive_without_attestation_fails_before_codesign(self) -> None:
        self.complete_gate()
        self.install_trace_shims()
        self.make_reused_archive(source_sha=self.sha, include_attestation=False)

        result = self.run_prepare(reuse_archive=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("attestation", (result.stderr + result.stdout).lower())
        self.assertEqual(self.trace_lines(), [])

    def test_local_prepare_holds_operation_through_artifact_completion(self) -> None:
        self.complete_gate()
        self.make_reused_archive(source_sha=self.sha, include_attestation=False)
        self.install_trace_shims(prepare_success=True)

        result = self.run_prepare()

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("Prepared local validation artifact", result.stdout)
        artifact = (
            self.root
            / ".build"
            / "releases"
            / "local"
            / "9.8.7-test.1"
            / "Cadence-9.8.7-test.1-arm64.dmg"
        )
        self.assertEqual(artifact.read_bytes(), b"fixture dmg\n")
        self.assertFalse(
            (self.root / ".build" / "cadence-release-operation.lock").exists()
        )
        self.assertEqual(
            self.trace_lines(),
            [
                "xcodegen",
                "xcodebuild-resolve",
                "xcodebuild-archive",
                "lipo",
                "codesign",
                "create-dmg",
            ],
        )

    def test_prepare_supervisor_preserves_requested_developer_directory(self) -> None:
        self.complete_gate()
        self.make_reused_archive(source_sha=self.sha, include_attestation=False)
        self.install_trace_shims(prepare_success=True)
        developer_trace = self.root / ".build" / "developer-directory.txt"

        result = self.run_prepare(
            extra_env={"DEVELOPER_TRACE_PATH": str(developer_trace)}
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(
            developer_trace.read_text(encoding="utf-8"),
            str(self.developer_directory),
        )

    def test_successful_prepare_retains_lock_until_resistant_group_drains(
        self,
    ) -> None:
        self.complete_gate()
        self.make_reused_archive(source_sha=self.sha, include_attestation=False)
        self.install_trace_shims(prepare_success=True)
        owner_pid_path = self.root / ".build" / "successful-owner.pid"
        resistant_pid_path = self.root / ".build" / "successful-resistant.pid"
        resistant_ready_path = self.root / ".build" / "successful-resistant.ready"
        environment = self.prepare_environment(
            {
                "SUCCESS_OWNER_PID_PATH": str(owner_pid_path),
                "SUCCESS_RESISTANT_PID_PATH": str(resistant_pid_path),
                "SUCCESS_RESISTANT_READY_PATH": str(resistant_ready_path),
            }
        )
        supervisor = subprocess.Popen(
            ["bash", str(self.scripts / "prepare_release.sh"), str(self.notes)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
        )
        competing_owner: subprocess.Popen[bytes] | None = None
        old_group: int | None = None
        supervisor_communicated = False
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and not (
                owner_pid_path.is_file()
                and resistant_pid_path.is_file()
                and resistant_ready_path.is_file()
            ):
                if supervisor.poll() is not None:
                    break
                time.sleep(0.01)
            if not (
                owner_pid_path.is_file()
                and resistant_pid_path.is_file()
                and resistant_ready_path.is_file()
            ):
                stdout, stderr = supervisor.communicate(timeout=10)
                supervisor_communicated = True
                self.fail(
                    "The successful resistant fixture did not become ready.\n"
                    + stderr
                    + stdout
                )
            self.assertTrue(owner_pid_path.is_file())
            self.assertTrue(resistant_pid_path.is_file())
            self.assertTrue(resistant_ready_path.is_file())
            old_group = int(owner_pid_path.read_text(encoding="ascii"))
            self.assertEqual(os.getpgid(int(resistant_pid_path.read_text())), old_group)

            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                try:
                    os.getpgid(old_group)
                except ProcessLookupError:
                    break
                time.sleep(0.01)
            else:
                self.fail("The successful preparation leader did not exit.")
            os.killpg(old_group, 0)

            lock_directory = (
                self.root / ".build" / "cadence-release-operation.lock"
            )
            lock_present_during_drain = (
                lock_directory / "operation.json"
            ).is_file()
            competing_owner = subprocess.Popen(
                [sys.executable, "-I", "-B", "-c", "import time; time.sleep(300)"],
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            competing = subprocess.run(
                [
                    sys.executable,
                    str(self.scripts / "release_contract.py"),
                    "release-operation-begin",
                    "--expect-sha",
                    self.sha,
                    "--release-mode",
                    "local",
                    "--operation-owner-pid",
                    str(competing_owner.pid),
                    "--root",
                    str(self.root),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertTrue(
                lock_present_during_drain,
                "Successful preparation removed its lock before group drain.",
            )
            self.assertNotEqual(
                competing.returncode,
                0,
                "A competing operation entered while the successful old group lived.",
            )
            stdout, stderr = supervisor.communicate(timeout=15)
            supervisor_communicated = True

            self.assertEqual(supervisor.returncode, 0, stderr + stdout)
            with self.assertRaises(ProcessLookupError):
                os.killpg(old_group, 0)
            self.assertFalse(lock_directory.exists())
            artifact = (
                self.root
                / ".build"
                / "releases"
                / "local"
                / "9.8.7-test.1"
                / "Cadence-9.8.7-test.1-arm64.dmg"
            )
            self.assertEqual(artifact.read_bytes(), b"fixture dmg\n")
        finally:
            if supervisor.poll() is None:
                supervisor.kill()
            if not supervisor_communicated:
                supervisor.communicate(timeout=5)
            if old_group is not None:
                try:
                    os.killpg(old_group, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if competing_owner is not None:
                competing_owner.terminate()
                competing_owner.wait(timeout=5)

    def test_release_gate_source_failure_stops_before_xcodegen(self) -> None:
        self.install_trace_shims()
        (self.root / "later.txt").write_text("later\n", encoding="utf-8")
        self.git("add", "later.txt")
        self.git("commit", "-q", "-m", "later")

        result = self.run_verify()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(self.tag, result.stderr + result.stdout)
        self.assertEqual(self.trace_lines(), [])

    def test_release_gate_skip_removes_stale_evidence_and_stops(self) -> None:
        self.complete_gate()
        self.install_trace_shims()
        attestation = (
            self.root
            / ".build"
            / "release-attestations"
            / f"{self.sha}.json"
        )
        self.assertTrue(attestation.is_file())

        result = self.run_verify(skip_xcodebuild=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires the full local Xcode gate", result.stderr)
        self.assertFalse(attestation.exists())
        self.assertEqual(self.trace_lines(), [])

    def test_release_gate_real_shell_topology_writes_attestation(self) -> None:
        self.install_trace_shims(verify_success=True)

        result = self.run_verify()

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("Full release gate attestation written", result.stdout)
        attestation = (
            self.root
            / ".build"
            / "release-attestations"
            / f"{self.sha}.json"
        )
        self.assertTrue(attestation.is_file())
        decoded = json.loads(attestation.read_text(encoding="utf-8"))
        self.assertEqual(decoded["source"]["gitSHA"], self.sha)
        self.assertEqual(decoded["source"]["tag"], self.tag)

    def test_release_fixture_full_gate_ignores_inherited_hosted_skip(self) -> None:
        self.install_trace_shims(verify_success=True)

        result = self.run_verify(
            extra_env={"CADENCE_SKIP_XCODEBUILD": "1"}
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("Full release gate attestation written", result.stdout)

    def test_release_validator_entrypoints_isolate_standard_library_imports(self) -> None:
        marker = self.root / "import-marker.txt"
        (self.scripts / "secrets.py").write_text(
            "import os\n"
            "from pathlib import Path\n"
            "marker = os.environ.get('CADENCE_IMPORT_MARKER')\n"
            "if marker:\n"
            "    Path(marker).write_text('imported\\n', encoding='utf-8')\n",
            encoding="utf-8",
        )
        environment = {
            **os.environ,
            "CADENCE_IMPORT_MARKER": str(marker),
        }

        direct = subprocess.run(
            [
                str(self.scripts / "release_contract.py"),
                "gate-begin",
                "--root",
                str(self.root),
            ],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

        self.assertNotEqual(direct.returncode, 0)
        self.assertFalse(marker.exists(), direct.stderr + direct.stdout)

        self.install_trace_shims()
        verified = self.run_verify(
            extra_env={"CADENCE_IMPORT_MARKER": str(marker)}
        )
        self.assertNotEqual(verified.returncode, 0)
        self.assertFalse(marker.exists(), verified.stderr + verified.stdout)

        prepared = self.run_prepare(
            extra_env={"CADENCE_IMPORT_MARKER": str(marker)}
        )
        self.assertNotEqual(prepared.returncode, 0)
        self.assertFalse(marker.exists(), prepared.stderr + prepared.stdout)

    def test_prepare_supervisor_forwards_signals_to_its_dedicated_group(self) -> None:
        owner_path = self.root / "supervised-owner.pid"
        group_path = self.root / "supervised-owner.pgid"
        ready_path = self.root / "supervised-ready.txt"
        forwarded_path = self.root / "supervised-forwarded.txt"
        resistant_path = self.root / "supervised-resistant.pid"
        (self.scripts / "prepare_release.sh").write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "trap 'printf forwarded > \"$FORWARDED_PATH\"; exit 42' TERM\n"
            "printf '%s' \"$$\" > \"$OWNER_PATH\"\n"
            "/usr/bin/python3 -I -B -c 'import os; from pathlib import Path; "
            "Path(os.environ[\"GROUP_PATH\"]).write_text(str(os.getpgrp()), "
            "encoding=\"ascii\")'\n"
            "/usr/bin/python3 -I -B -c 'import os, signal, time; "
            "from pathlib import Path; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
            "Path(os.environ[\"RESISTANT_PATH\"]).write_text(str(os.getpid()), "
            "encoding=\"ascii\"); time.sleep(300)' "
            "</dev/null >/dev/null &\n"
            "resistant_pid=$!\n"
            "disown \"$resistant_pid\" 2>/dev/null || true\n"
            "printf ready > \"$READY_PATH\"\n"
            "while :; do sleep 1; done\n",
            encoding="utf-8",
        )
        environment = {
            **os.environ,
            "FORWARDED_PATH": str(forwarded_path),
            "GROUP_PATH": str(group_path),
            "OWNER_PATH": str(owner_path),
            "READY_PATH": str(ready_path),
            "RESISTANT_PATH": str(resistant_path),
        }
        supervisor = subprocess.Popen(
            [
                sys.executable,
                str(RELEASE_CONTRACT),
                "supervise-prepare",
                "--root",
                str(self.root),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
        )
        owner_pid: int | None = None
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and not (
                ready_path.is_file() and resistant_path.is_file()
            ):
                if supervisor.poll() is not None:
                    break
                time.sleep(0.01)
            self.assertTrue(ready_path.is_file())
            self.assertTrue(resistant_path.is_file())
            owner_pid = int(owner_path.read_text(encoding="ascii"))
            owner_group = int(group_path.read_text(encoding="ascii"))
            self.assertEqual(owner_pid, owner_group)
            self.assertNotEqual(owner_pid, supervisor.pid)

            supervisor.send_signal(signal.SIGTERM)
            stdout, stderr = supervisor.communicate(timeout=10)

            self.assertEqual(supervisor.returncode, 42, stderr + stdout)
            self.assertEqual(
                forwarded_path.read_text(encoding="utf-8"), "forwarded"
            )
            with self.assertRaises(ProcessLookupError):
                os.killpg(owner_pid, 0)
        finally:
            if supervisor.poll() is None:
                supervisor.kill()
                supervisor.wait(timeout=5)
            if owner_pid is not None:
                try:
                    os.killpg(owner_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_signalled_prepare_retains_lock_until_resistant_group_member_exits(
        self,
    ) -> None:
        self.complete_gate()
        self.install_trace_shims()
        ready_path = self.root / ".build" / "resistant-xcodegen-ready.txt"
        resistant_pid_path = self.root / ".build" / "resistant-xcodegen.pid"
        xcodegen = self.shim_directory / "xcodegen"
        xcodegen.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "trap 'exit 143' TERM\n"
            "/usr/bin/python3 -I -B -c 'import os, signal, time; "
            "from pathlib import Path; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
            "Path(os.environ[\"RESISTANT_PID_PATH\"]).write_text(str(os.getpid()), "
            "encoding=\"ascii\"); time.sleep(300)' "
            "</dev/null >/dev/null 2>&1 &\n"
            "printf ready > \"$RESISTANT_READY_PATH\"\n"
            "while :; do sleep 1; done\n",
            encoding="utf-8",
        )
        xcodegen.chmod(0o755)
        environment = self.prepare_environment(
            {
                "RESISTANT_PID_PATH": str(resistant_pid_path),
                "RESISTANT_READY_PATH": str(ready_path),
            }
        )
        supervisor = subprocess.Popen(
            ["bash", str(self.scripts / "prepare_release.sh"), str(self.notes)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
        )
        lock_directory = (
            self.root / ".build" / "cadence-release-operation.lock"
        )
        owner_pid: int | None = None
        recovery_owner: subprocess.Popen[bytes] | None = None
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and not (
                ready_path.is_file()
                and resistant_pid_path.is_file()
                and (lock_directory / "operation.json").is_file()
            ):
                if supervisor.poll() is not None:
                    break
                time.sleep(0.01)
            if not ready_path.is_file() and supervisor.poll() is not None:
                stdout, stderr = supervisor.communicate(timeout=5)
                self.fail(
                    f"Preparation exited before resistant shim: {stderr}{stdout}"
                )
            self.assertTrue(
                ready_path.is_file(),
                f"supervisor={supervisor.poll()} trace={self.trace_lines()} "
                f"lock={lock_directory.exists()}",
            )
            self.assertTrue((lock_directory / "operation.json").is_file())
            manifest = json.loads(
                (lock_directory / "operation.json").read_text(encoding="utf-8")
            )
            owner_pid = manifest["owner"]["pid"]

            supervisor.send_signal(signal.SIGTERM)
            stdout, stderr = supervisor.communicate(timeout=15)

            self.assertEqual(supervisor.returncode, 143, stderr + stdout)
            with self.assertRaises(ProcessLookupError):
                os.killpg(owner_pid, 0)
            self.assertTrue(
                (lock_directory / "operation.json").is_file(),
                "Abnormal preparation must retain authenticated lock evidence.",
            )

            recovery_owner = subprocess.Popen(
                [sys.executable, "-I", "-B", "-c", "import time; time.sleep(300)"],
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            recovered = subprocess.run(
                [
                    sys.executable,
                    str(self.scripts / "release_contract.py"),
                    "release-operation-begin",
                    "--expect-sha",
                    self.sha,
                    "--release-mode",
                    "local",
                    "--operation-owner-pid",
                    str(recovery_owner.pid),
                    "--root",
                    str(self.root),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(recovered.returncode, 0, recovered.stderr)
            self.assertIn("recovered stale release operation", recovered.stderr.lower())
            token = ReleaseProvenanceTests.shell_values(recovered.stdout)[
                "RELEASE_OPERATION_TOKEN"
            ]
            recovery_owner.terminate()
            recovery_owner.wait(timeout=5)
            ended = subprocess.run(
                [
                    sys.executable,
                    str(self.scripts / "release_contract.py"),
                    "release-operation-end",
                    "--release-mode",
                    "local",
                    "--operation-token",
                    token,
                    "--root",
                    str(self.root),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(ended.returncode, 0, ended.stderr)
        finally:
            if supervisor.poll() is None:
                supervisor.kill()
                supervisor.wait(timeout=5)
            if owner_pid is not None:
                try:
                    os.killpg(owner_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if recovery_owner is not None:
                recovery_owner.terminate()
                recovery_owner.wait(timeout=5)

    def test_late_tag_drift_stops_before_artifact_publication(self) -> None:
        self.complete_gate()
        self.make_reused_archive(source_sha=self.sha, include_attestation=False)
        alternate = self.git("commit-tree", "HEAD^{tree}", "-m", "alternate").stdout.strip()
        self.install_trace_shims(
            prepare_success=True,
            codesign_moves_tag_to=alternate,
        )

        result = self.run_prepare()

        self.assertNotEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(
            self.git("rev-parse", f"refs/tags/{self.tag}^{{commit}}").stdout.strip(),
            alternate,
        )
        artifact = (
            self.root
            / ".build"
            / "releases"
            / "local"
            / "9.8.7-test.1"
            / "Cadence-9.8.7-test.1-arm64.dmg"
        )
        self.assertFalse(artifact.exists())
        self.assertIn("codesign", self.trace_lines())

    def run_prepare(
        self,
        *,
        reuse_archive: bool = False,
        extra_env: dict[str, str] | None = None,
        release_notes: str | Path | None = None,
        use_default_notes: bool = False,
        cwd: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        command = ["bash", str(self.scripts / "prepare_release.sh")]
        if not use_default_notes:
            command.append(str(self.notes if release_notes is None else release_notes))
        environment = self.prepare_environment(extra_env)
        if reuse_archive:
            environment["CADENCE_REUSE_ARCHIVE"] = "1"
        return subprocess.run(
            command,
            cwd=cwd,
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def prepare_environment(
        self, extra_env: dict[str, str] | None = None
    ) -> dict[str, str]:
        return {
            **os.environ,
            "CADENCE_RELEASE_MODE": "local",
            "DEVELOPER_DIR": str(self.developer_directory),
            "PATH": f"{self.shim_directory}:{os.environ['PATH']}",
            "TRACE_PATH": str(self.trace),
            **(extra_env or {}),
        }

    def run_verify(
        self,
        *,
        skip_xcodebuild: bool = False,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        environment = {
            **os.environ,
            "DEVELOPER_DIR": str(self.developer_directory),
            "CADENCE_IMAGE_PYTHON": str(self.shim_directory / "image-python"),
            "PATH": f"{self.shim_directory}:{os.environ['PATH']}",
            "SHIM_INFO_PLIST": str(self.shim_directory / "Info.plist.fixture"),
            "TRACE_PATH": str(self.trace),
            **(extra_env or {}),
        }
        environment.pop("CADENCE_SKIP_XCODEBUILD", None)
        if skip_xcodebuild:
            environment["CADENCE_SKIP_XCODEBUILD"] = "1"
        return subprocess.run(
            ["bash", str(self.scripts / "verify.sh"), "--release-attestation"],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def complete_gate(self) -> None:
        begin = subprocess.run(
            [
                sys.executable,
                str(self.scripts / "release_contract.py"),
                "gate-begin",
                "--root",
                str(self.root),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(begin.returncode, 0, begin.stderr)
        gate_session = ReleaseProvenanceTests.shell_values(begin.stdout)[
            "RELEASE_GATE_SESSION"
        ]
        receipt_arguments = [
            argument
            for receipt in GATE_RECEIPTS
            for argument in ("--gate-receipt", receipt)
        ]
        result = subprocess.run(
            [
                sys.executable,
                str(self.scripts / "release_contract.py"),
                "gate-complete",
                "--source-sha",
                self.sha,
                "--gate-session",
                gate_session,
                *receipt_arguments,
                "--root",
                str(self.root),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def make_reused_archive(
        self, *, source_sha: str, include_attestation: bool
    ) -> None:
        attestation_path = (
            self.root
            / ".build"
            / "release-attestations"
            / f"{self.sha}.json"
        )
        attestation = attestation_path.read_bytes()
        archive = (
            self.root
            / ".build"
            / "Release"
            / "local"
            / "Cadence.xcarchive"
        )
        contents = (
            archive
            / "Products"
            / "Applications"
            / "Cadence.app"
            / "Contents"
        )
        contents.mkdir(parents=True)
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump(
                {
                    "CFBundleShortVersionString": "9.8.7",
                    "CFBundleVersion": "1",
                    "CFBundleIdentifier": "com.qenterra.cadence",
                    "CadenceSourceGitSHA": source_sha,
                    "CadenceReleaseTag": self.tag,
                    "CadenceFullGateAttestationSHA256": hashlib.sha256(
                        attestation
                    ).hexdigest(),
                },
                handle,
            )
        if include_attestation:
            (archive / "CadenceReleaseAttestation.json").write_bytes(attestation)

    def install_trace_shims(
        self,
        *,
        xcodegen_mutates_project: bool = False,
        xcodebuild_resolve_mutates_package: bool = False,
        verify_success: bool = False,
        prepare_success: bool = False,
        codesign_moves_tag_to: str | None = None,
    ) -> None:
        if verify_success:
            with (self.shim_directory / "Info.plist.fixture").open("wb") as handle:
                plistlib.dump(
                    {
                        "CFBundleIconFile": "Cadence",
                        "CFBundleIconName": "Cadence",
                        "CFBundleDocumentTypes": [
                            {
                                "CFBundleTypeRole": "Viewer",
                                "LSHandlerRank": "Alternate",
                                "CFBundleTypeExtensions": [
                                    "aac",
                                    "aif",
                                    "aiff",
                                    "flac",
                                    "m4a",
                                    "mp3",
                                    "wav",
                                ],
                            }
                        ],
                    },
                    handle,
                )
            image_python = self.shim_directory / "image-python"
            image_python.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "exit 0\n",
                encoding="utf-8",
            )
            image_python.chmod(0o755)
        for command in (
            "xcodegen",
            "xcodebuild",
            "codesign",
            "xcrun",
            "spctl",
            "lipo",
            "ditto",
            "swiftformat",
            "swiftlint",
            "xcbeautify",
        ):
            body = ["#!/usr/bin/env bash", "set -euo pipefail"]
            body.append("mkdir -p \"$(dirname \"$TRACE_PATH\")\"")
            if command == "xcodebuild":
                body.append(
                    "if [[ -n \"${DEVELOPER_TRACE_PATH:-}\" ]]; then "
                    "printf '%s' \"${DEVELOPER_DIR:-}\" > \"$DEVELOPER_TRACE_PATH\"; fi"
                )
                body.append(
                    "if [[ \" $* \" == *\" -resolvePackageDependencies \"* ]]; then"
                )
                body.append("  echo xcodebuild-resolve >> \"$TRACE_PATH\"")
                if xcodebuild_resolve_mutates_package:
                    body.append(
                        "  echo '# dependency drift' >> "
                        "Cadence.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
                    )
                body.append("elif [[ \" $* \" == *\" archive \"* ]]; then")
                body.append("  echo xcodebuild-archive >> \"$TRACE_PATH\"")
                body.append("else")
                body.append("  echo xcodebuild-test >> \"$TRACE_PATH\"")
                if verify_success:
                    body.extend(
                        [
                            "  app=\"$PWD/.build/DerivedData/Build/Products/Debug/Cadence.app\"",
                            "  mkdir -p \"$app/Contents/Resources\"",
                            "  cp \"$SHIM_INFO_PLIST\" \"$app/Contents/Info.plist\"",
                            "  : > \"$app/Contents/Resources/Cadence.icns\"",
                            "  : > \"$app/Contents/Resources/Assets.car\"",
                        ]
                    )
                body.append("fi")
            elif command == "xcrun" and verify_success:
                body.append("echo xcrun >> \"$TRACE_PATH\"")
                body.append(
                    "printf '%s\\n' '[ { \"Appearance\" : "
                    "\"NSAppearanceNameAqua\", \"Name\" : "
                    "\"Cadence_Assets\\/system-light\" }, "
                    "{ \"Appearance\" : \"NSAppearanceNameDarkAqua\", "
                    "\"Name\" : \"Cadence_Assets\\/system-dark\" } ]'"
                )
            elif command == "xcbeautify":
                body.append("cat >/dev/null")
            elif command == "swiftlint":
                body.append("echo swiftlint >> \"$TRACE_PATH\"")
                body.append("printf '%s\\n' '[]'")
            elif command == "lipo" and prepare_success:
                body.append("echo lipo >> \"$TRACE_PATH\"")
                body.append("printf '%s\\n' arm64")
            else:
                body.append(f"echo {shlex.quote(command)} >> \"$TRACE_PATH\"")
            if command == "codesign" and codesign_moves_tag_to is not None:
                body.append(
                    "env -u DEVELOPER_DIR /usr/bin/git -C "
                    f"{shlex.quote(str(self.root))} update-ref "
                    f"refs/tags/{shlex.quote(self.tag)} "
                    f"{shlex.quote(codesign_moves_tag_to)}"
                )
            if command == "xcodegen" and xcodegen_mutates_project:
                body.append("echo '# generated drift' >> project.yml")
            path = self.shim_directory / command
            path.write_text("\n".join(body) + "\n", encoding="utf-8")
            path.chmod(0o755)

    def trace_lines(self) -> list[str]:
        if not self.trace.exists():
            return []
        return self.trace.read_text(encoding="utf-8").splitlines()

    def git(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", "-C", str(self.root), *arguments],
            check=True,
            capture_output=True,
            text=True,
            env={**os.environ, "LC_ALL": "C"},
        )

    def _write_release_surfaces(self) -> None:
        manifest = {
            "schemaVersion": 1,
            "product": {
                "name": "Cadence",
                "artifactStem": "Cadence",
                "bundleIdentifier": "com.qenterra.cadence",
                "humanReleaseName": "Cadence 9.8.7 Test 1 (1)",
            },
            "release": {
                "marketingVersion": "9.8.7",
                "build": 1,
                "channel": "test",
                "iteration": 1,
                "version": "9.8.7-test.1",
                "tag": self.tag,
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
            "artifacts": {
                "installer": "Cadence-9.8.7-test.1-arm64.dmg",
                "update": "Cadence-9.8.7-test.1-arm64.zip",
                "checksums": "Cadence-9.8.7-test.1-SHA256SUMS.txt",
            },
        }
        (self.root / "release-contract.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )
        (self.root / ".gitignore").write_text(
            ".build/\nDeveloper/\nshims/\n", encoding="utf-8"
        )
        (self.root / "project.yml").write_text(
            'deploymentTarget:\n  macOS: "26.0"\n'
            'MARKETING_VERSION: "9.8.7"\n'
            'CURRENT_PROJECT_VERSION: "1"\n'
            'PRODUCT_BUNDLE_IDENTIFIER: com.qenterra.cadence\n',
            encoding="utf-8",
        )
        package_resolved = (
            self.root
            / "Cadence.xcodeproj"
            / "project.xcworkspace"
            / "xcshareddata"
            / "swiftpm"
            / "Package.resolved"
        )
        package_resolved.parent.mkdir(parents=True)
        package_resolved.write_text('{"pins":[],"version":3}\n', encoding="utf-8")
        (self.root / "README.md").write_text(
            "Version 9.8.7-test.1\n"
            "Cadence-9.8.7-test.1-arm64.dmg\n"
            "This build is not notarized; Gatekeeper may show friction.\n",
            encoding="utf-8",
        )
        (self.root / "CHANGELOG.md").write_text(
            "## [9.8.7-test.1]\n", encoding="utf-8"
        )
        updates = self.root / "docs" / "UPDATES.md"
        updates.parent.mkdir()
        updates.write_text(
            "Cadence 9.8.7 Test 1 (1)\n"
            "v9.8.7-test.1\n"
            "Cadence-9.8.7-test.1-arm64.dmg\n"
            "Cadence-9.8.7-test.1-arm64.zip\n"
            "Cadence-9.8.7-test.1-SHA256SUMS.txt\n",
            encoding="utf-8",
        )
        icon_manifest = self.root / "icon" / "Cadence.icon" / "icon.json"
        icon_manifest.parent.mkdir(parents=True)
        icon_manifest.write_text(
            json.dumps(
                {
                    "supported-platforms": {
                        "squares": "shared",
                        "circles": ["watchOS"],
                    },
                    "groups": [
                        {
                            "layers": [
                                {
                                    "fill-specializations": [
                                        {},
                                        {
                                            "appearance": "light",
                                            "value": "system-dark",
                                        },
                                    ]
                                }
                            ]
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        release_tests = self.root / "Tests" / "ReleaseContractTests"
        release_tests.mkdir(parents=True)
        for name in (
            "test_release_contract.py",
            "test_release_provenance.py",
            "test_dmg_background.py",
            "test_swiftlint_debt_gate.py",
            "test_ui_component_ownership.py",
        ):
            (release_tests / name).write_text(
                "import unittest\n\n"
                "class FixtureTest(unittest.TestCase):\n"
                "    def test_fixture(self):\n"
                "        self.assertTrue(True)\n",
                encoding="utf-8",
            )
        for script_name in ("verify_localization.sh", "verify_periphery.sh"):
            script = self.scripts / script_name
            script.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            script.chmod(0o755)
        create_dmg = self.scripts / "create_dmg.sh"
        create_dmg.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "echo create-dmg >> \"$TRACE_PATH\"\n"
            "if [[ -n \"${SUCCESS_RESISTANT_PID_PATH:-}\" ]]; then\n"
            "  printf '%s' \"$PPID\" > \"$SUCCESS_OWNER_PID_PATH\"\n"
            "  (\n"
            "    trap '' HUP INT TERM\n"
            "    printf 'ready' > \"$SUCCESS_RESISTANT_READY_PATH\"\n"
            "    while :; do sleep 300 || true; done\n"
            "  ) </dev/null >/dev/null 2>&1 &\n"
            "  resistant_pid=$!\n"
            "  printf '%s' \"$resistant_pid\" > \"$SUCCESS_RESISTANT_PID_PATH\"\n"
            "  disown \"$resistant_pid\" 2>/dev/null || true\n"
            "  while [[ ! -f \"$SUCCESS_RESISTANT_READY_PATH\" ]]; do\n"
            "    if ! kill -0 \"$resistant_pid\" 2>/dev/null; then\n"
            "      echo 'resistant fixture exited before ready' >&2\n"
            "      exit 1\n"
            "    fi\n"
            "    sleep 0.01\n"
            "  done\n"
            "fi\n"
            "printf 'fixture dmg\\n' > \"$2\"\n",
            encoding="utf-8",
        )
        create_dmg.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
