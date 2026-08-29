#!/usr/bin/env -S python3 -I -B
"""Validate Cadence release surfaces against release-contract.json."""

from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import hmac
import json
import os
import plistlib
import re
import secrets
import signal
import shlex
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
ATTESTATION_KIND = "cadence-full-gate"
ATTESTATION_SCHEMA_VERSION = 1
ATTESTATION_COMMAND = "scripts/verify.sh --release-attestation"
GATE_SESSION_SCHEMA_VERSION = 1
GATE_SESSION_PATTERN = re.compile(r"^[0-9a-f]{64}$")
REQUIRED_GATE_RECEIPTS = frozenset(
    {
        "xcode-tests",
        "localization",
        "periphery",
        "built-product",
        "asset-catalog",
    }
)
PUBLISHED_TAG_COMMITS = {
    "v0.2.0-beta.1": "730f61fe837493d550f335edb0ded97d5c19562a",
}
SAFE_COMPONENT_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")
RELEASE_INPUT_DIRECTORIES = (
    "Sources",
    "Tests",
    "scripts",
    "release",
    "icon",
    "Cadence.xcodeproj",
)
RELEASE_INPUT_FILES = (
    ".periphery-baseline.json",
    ".swiftformat",
    ".swiftlint.yml",
    "project.yml",
    "release-contract.json",
    "appcast.xml",
    "README.md",
    "CHANGELOG.md",
    "docs/UPDATES.md",
    "Cadence.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
)
RELEASE_OPERATION_SCHEMA_VERSION = 3
RELEASE_OPERATION_RELATIVE_PATH = Path(".build/cadence-release-operation.lock")
RELEASE_SUPERVISOR_GRACE_SECONDS = 1.0
RELEASE_SUPERVISOR_POLL_SECONDS = 0.02


class ReleaseContractError(RuntimeError):
    """A release invariant failed before a release side effect was allowed."""


@dataclass(frozen=True)
class ReleaseSource:
    sha: str
    tag: str


@dataclass(frozen=True)
class ReleasePreflight:
    source: ReleaseSource
    attestation_path: Path
    attestation_sha256: str
    gate_session: str = ""


def load_manifest(root: Path) -> dict[str, Any]:
    path = root / "release-contract.json"
    try:
        metadata = os.lstat(path)
    except FileNotFoundError as error:
        raise ReleaseContractError("release-contract.json is missing.") from error
    if not stat.S_ISREG(metadata.st_mode):
        raise ReleaseContractError(
            "release-contract.json must be a regular file inside the source tree."
        )
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseContractError(
            "release-contract.json is not valid UTF-8 JSON."
        ) from error
    if not isinstance(decoded, dict):
        raise ReleaseContractError("release-contract.json must contain one JSON object.")
    _validate_manifest_schema(decoded)
    return decoded


def _validate_manifest_schema(manifest: dict[str, Any]) -> None:
    expected: dict[str, dict[str, type]] = {
        "product": {
            "name": str,
            "artifactStem": str,
            "bundleIdentifier": str,
            "humanReleaseName": str,
        },
        "release": {
            "marketingVersion": str,
            "build": int,
            "channel": str,
            "iteration": int,
            "version": str,
            "tag": str,
        },
        "platform": {
            "name": str,
            "minimumVersion": str,
            "architecture": str,
        },
        "distribution": {
            "signing": str,
            "notarized": bool,
            "gatekeeperDisclosure": bool,
        },
        "artifacts": {
            "installer": str,
            "update": str,
            "checksums": str,
        },
    }
    if manifest.get("schemaVersion") != 1:
        raise ReleaseContractError("Release manifest schemaVersion must be integer 1.")
    for section_name, fields in expected.items():
        section = manifest.get(section_name)
        if not isinstance(section, dict):
            raise ReleaseContractError(
                f"Release manifest section {section_name!r} must be an object."
            )
        for field_name, field_type in fields.items():
            value = section.get(field_name)
            if field_type is int:
                valid = isinstance(value, int) and not isinstance(value, bool)
            else:
                valid = isinstance(value, field_type)
            if not valid:
                raise ReleaseContractError(
                    "Release manifest field "
                    f"{section_name}.{field_name} must be {field_type.__name__}."
                )


def _run_git(root: Path, *arguments: str) -> bytes:
    environment = {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }
    environment.pop("DEVELOPER_DIR", None)
    environment["LC_ALL"] = "C"
    environment["GIT_NO_REPLACE_OBJECTS"] = "1"
    try:
        result = subprocess.run(
            [
                "/usr/bin/git",
                "-c",
                "core.fsmonitor=false",
                "-c",
                "core.untrackedCache=false",
                "-c",
                "core.filemode=true",
                "-C",
                str(root),
                *arguments,
            ],
            check=True,
            capture_output=True,
            env=environment,
        )
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode("utf-8", errors="replace").strip()
        raise ReleaseContractError(
            f"Git could not validate release source: {detail or 'command failed'}."
        ) from error
    return result.stdout


def _validated_sha(value: str, label: str) -> str:
    if SHA_PATTERN.fullmatch(value) is None:
        raise ReleaseContractError(
            f"{label} must be one exact 40-character lowercase Git SHA."
        )
    return value


def validate_release_source(
    root: Path = ROOT,
    expect_sha: str | None = None,
) -> ReleaseSource:
    root = root.resolve()
    top_level = Path(
        _run_git(root, "rev-parse", "--show-toplevel")
        .decode("utf-8", errors="strict")
        .strip()
    ).resolve()
    if top_level != root:
        raise ReleaseContractError(
            f"Git worktree {top_level} does not match release root {root}."
        )
    replacement_refs = _run_git(
        root, "for-each-ref", "--format=%(refname)", "refs/replace/"
    )
    if replacement_refs:
        refs = replacement_refs.decode("utf-8", errors="replace").splitlines()
        raise ReleaseContractError(
            f"Git replace refs are active ({', '.join(refs)}); remove them before release."
        )
    tag = str(load_manifest(root)["release"]["tag"])
    if not tag or "\n" in tag or "\r" in tag:
        raise ReleaseContractError("The release contract tag is invalid.")
    try:
        _run_git(root, "check-ref-format", f"refs/tags/{tag}")
    except ReleaseContractError as error:
        raise ReleaseContractError(
            f"The release contract tag {tag!r} is not a safe Git tag."
        ) from error

    source_sha = _validated_sha(
        _run_git(root, "rev-parse", "--verify", "HEAD^{commit}")
        .decode("ascii")
        .strip(),
        "HEAD",
    )
    try:
        tag_sha = _validated_sha(
            _run_git(
                root,
                "rev-parse",
                "--verify",
                f"refs/tags/{tag}^{{commit}}",
            )
            .decode("ascii")
            .strip(),
            f"Release tag {tag}",
        )
    except ReleaseContractError as error:
        raise ReleaseContractError(
            f"Release tag {tag} does not resolve to a commit."
        ) from error

    published_sha = PUBLISHED_TAG_COMMITS.get(tag)
    if published_sha is not None and tag_sha != published_sha:
        raise ReleaseContractError(
            f"Published release tag {tag} is pinned to {published_sha}, not {tag_sha}. "
            "Never move or reuse a published tag."
        )

    if source_sha != tag_sha:
        raise ReleaseContractError(
            f"Release tag {tag} resolves to {tag_sha}, but HEAD is {source_sha}. "
            "Never reuse or move a published tag; bump the release contract."
        )
    if expect_sha is not None:
        expected = _validated_sha(expect_sha, "Expected source SHA")
        if source_sha != expected:
            raise ReleaseContractError(
                f"Release source changed: expected {expected}, but HEAD is {source_sha}."
            )

    index_flags = _run_git(root, "ls-files", "-v", "-z")
    for entry in index_flags.split(b"\0"):
        if not entry:
            continue
        marker = chr(entry[0])
        path = entry[2:].decode("utf-8", errors="replace")
        if marker.upper() == "S":
            raise ReleaseContractError(
                f"Tracked path {path!r} has skip-worktree set; release byte "
                "cleanliness cannot be proven."
            )
        if marker.islower():
            raise ReleaseContractError(
                f"Tracked path {path!r} has assume-unchanged set; release byte "
                "cleanliness cannot be proven."
            )
    _validate_exact_git_tree(root, source_sha)
    _validate_release_input_inventory(root)
    return ReleaseSource(sha=source_sha, tag=tag)


def _parse_git_tree(data: bytes) -> dict[str, tuple[str, str]]:
    result: dict[str, tuple[str, str]] = {}
    for raw_entry in data.split(b"\0"):
        if not raw_entry:
            continue
        try:
            metadata, raw_path = raw_entry.split(b"\t", 1)
            raw_mode, object_type, raw_oid = metadata.split(b" ", 2)
            path = raw_path.decode("utf-8", errors="surrogateescape")
            mode = raw_mode.decode("ascii")
            oid = raw_oid.decode("ascii")
        except (UnicodeDecodeError, ValueError) as error:
            raise ReleaseContractError("Git returned a malformed release tree.") from error
        if object_type != b"blob" or mode not in {"100644", "100755"}:
            raise ReleaseContractError(
                f"Tracked release path {path!r} is not a supported physical file."
            )
        if SHA_PATTERN.fullmatch(oid) is None or path in result:
            raise ReleaseContractError("Git returned an ambiguous release tree.")
        result[path] = (mode, oid)
    return result


def _parse_git_index(data: bytes) -> dict[str, tuple[str, str]]:
    result: dict[str, tuple[str, str]] = {}
    for raw_entry in data.split(b"\0"):
        if not raw_entry:
            continue
        try:
            metadata, raw_path = raw_entry.split(b"\t", 1)
            raw_mode, raw_oid, stage = metadata.split(b" ", 2)
            path = raw_path.decode("utf-8", errors="surrogateescape")
            mode = raw_mode.decode("ascii")
            oid = raw_oid.decode("ascii")
        except (UnicodeDecodeError, ValueError) as error:
            raise ReleaseContractError("Git returned a malformed release index.") from error
        if stage != b"0" or mode not in {"100644", "100755"}:
            raise ReleaseContractError(
                f"Tracked release path {path!r} has an unsupported index entry."
            )
        if SHA_PATTERN.fullmatch(oid) is None or path in result:
            raise ReleaseContractError("Git returned an ambiguous release index.")
        result[path] = (mode, oid)
    return result


def _raw_worktree_blob_oid(path: Path, expected_mode: str, label: str) -> str:
    try:
        before = os.lstat(path)
    except FileNotFoundError as error:
        raise ReleaseContractError(f"Tracked release input {label!r} is missing.") from error
    if not stat.S_ISREG(before.st_mode):
        raise ReleaseContractError(
            f"Tracked release input {label!r} must be a physical regular file."
        )
    if before.st_nlink != 1:
        raise ReleaseContractError(
            f"Tracked release input {label!r} must not be a hard link."
        )
    actual_mode = "100755" if before.st_mode & stat.S_IXUSR else "100644"
    if actual_mode != expected_mode:
        raise ReleaseContractError(
            f"Tracked release input {label!r} does not match its tagged Git mode."
        )
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise ReleaseContractError(
            f"Tracked release input {label!r} could not be opened safely."
        ) from error
    digest = hashlib.sha1(usedforsecurity=False)
    with os.fdopen(descriptor, "rb", closefd=True) as handle:
        opened = os.fstat(handle.fileno())
        if (
            opened.st_dev != before.st_dev
            or opened.st_ino != before.st_ino
            or opened.st_size != before.st_size
            or opened.st_mode != before.st_mode
            or opened.st_nlink != 1
            or not stat.S_ISREG(opened.st_mode)
        ):
            raise ReleaseContractError(
                f"Tracked release input {label!r} changed while it was opened."
            )
        digest.update(f"blob {opened.st_size}\0".encode("ascii"))
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
        after_read = os.fstat(handle.fileno())
    try:
        after_path = os.lstat(path)
    except FileNotFoundError as error:
        raise ReleaseContractError(
            f"Tracked release input {label!r} disappeared during validation."
        ) from error
    if (
        after_read.st_dev != opened.st_dev
        or after_read.st_ino != opened.st_ino
        or after_read.st_size != opened.st_size
        or after_read.st_mode != opened.st_mode
        or after_path.st_dev != opened.st_dev
        or after_path.st_ino != opened.st_ino
        or after_path.st_size != opened.st_size
        or after_path.st_mode != opened.st_mode
        or after_path.st_nlink != 1
    ):
        raise ReleaseContractError(
            f"Tracked release input {label!r} changed during validation."
        )
    return digest.hexdigest()


def _validate_exact_git_tree(root: Path, source_sha: str) -> None:
    tagged_tree = _parse_git_tree(
        _run_git(root, "ls-tree", "-r", "-z", "--full-tree", source_sha)
    )
    index = _parse_git_index(_run_git(root, "ls-files", "--stage", "-z"))
    if index != tagged_tree:
        raise ReleaseContractError(
            "Release index is dirty; it must exactly match the tagged Git tree."
        )

    untracked = [
        entry.decode("utf-8", errors="surrogateescape")
        for entry in _run_git(
            root, "ls-files", "--others", "--exclude-standard", "-z"
        ).split(b"\0")
        if entry
    ]
    if untracked:
        raise ReleaseContractError(
            "Release source is dirty; remove untracked paths including "
            f"{untracked[0]!r}."
        )

    for relative, (mode, expected_oid) in tagged_tree.items():
        actual_oid = _raw_worktree_blob_oid(root / relative, mode, relative)
        if actual_oid != expected_oid:
            raise ReleaseContractError(
                "Release source is dirty: tracked release input "
                f"{relative!r} does not match its tagged Git blob."
            )


def _validate_release_input_inventory(root: Path) -> None:
    tracked = {
        entry.decode("utf-8", errors="surrogateescape")
        for entry in _run_git(root, "ls-files", "-z").split(b"\0")
        if entry
    }

    def validate_entry(path: Path) -> None:
        relative = path.relative_to(root).as_posix()
        try:
            metadata = os.lstat(path)
        except FileNotFoundError as error:
            raise ReleaseContractError(
                f"Release input {relative!r} disappeared during validation."
            ) from error
        if stat.S_ISLNK(metadata.st_mode):
            raise ReleaseContractError(
                f"Release input {relative!r} must not be a symlink."
            )
        if not stat.S_ISREG(metadata.st_mode):
            raise ReleaseContractError(
                f"Release input {relative!r} must be a regular file."
            )
        if metadata.st_nlink != 1:
            raise ReleaseContractError(
                f"Release input {relative!r} must not be a hard link."
            )
        if relative not in tracked:
            raise ReleaseContractError(
                f"Untracked release input {relative!r} is present, even if Git ignores it."
            )

    for directory_name in RELEASE_INPUT_DIRECTORIES:
        directory = root / directory_name
        if not directory.exists() and not directory.is_symlink():
            continue
        directory_metadata = os.lstat(directory)
        if stat.S_ISLNK(directory_metadata.st_mode) or not stat.S_ISDIR(
            directory_metadata.st_mode
        ):
            raise ReleaseContractError(
                f"Release input root {directory_name!r} must be a physical directory."
            )
        for current_root, directory_names, file_names in os.walk(
            directory, followlinks=False
        ):
            current = Path(current_root)
            for directory_name_entry in list(directory_names):
                candidate = current / directory_name_entry
                metadata = os.lstat(candidate)
                if stat.S_ISLNK(metadata.st_mode):
                    relative = candidate.relative_to(root).as_posix()
                    raise ReleaseContractError(
                        f"Release input directory {relative!r} must not be a symlink."
                    )
            for file_name in file_names:
                validate_entry(current / file_name)

    for relative_name in RELEASE_INPUT_FILES:
        candidate = root / relative_name
        if candidate.exists() or candidate.is_symlink():
            validate_entry(candidate)


def canonical_attestation_bytes(source: ReleaseSource) -> bytes:
    data = {
        "kind": ATTESTATION_KIND,
        "schemaVersion": ATTESTATION_SCHEMA_VERSION,
        "source": {"gitSHA": source.sha, "tag": source.tag},
        "verification": {
            "command": ATTESTATION_COMMAND,
            "result": "passed",
        },
    }
    return (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode(
        "utf-8"
    )


def _fixed_directory(
    root: Path,
    relative: Path,
    label: str,
    *,
    create: bool = False,
) -> Path:
    trusted_root = root.resolve()
    if relative.is_absolute() or ".." in relative.parts:
        raise ReleaseContractError(f"{label} is not a fixed repository path.")
    current = trusted_root
    for component in relative.parts:
        current = current / component
        try:
            metadata = os.lstat(current)
        except FileNotFoundError:
            if create:
                try:
                    current.mkdir()
                except FileExistsError:
                    pass
                metadata = os.lstat(current)
            else:
                continue
        if stat.S_ISLNK(metadata.st_mode):
            raise ReleaseContractError(f"{label} contains symlink {current}.")
        if not stat.S_ISDIR(metadata.st_mode):
            raise ReleaseContractError(f"{label} contains non-directory {current}.")
    return trusted_root / relative


def _require_physical_ancestry(path: Path, root: Path, label: str) -> Path:
    trusted_root = root.resolve()
    candidate = Path(os.path.abspath(path))
    if not candidate.is_relative_to(trusted_root):
        raise ReleaseContractError(
            f"{label} is outside the allowed release directory: {candidate}."
        )
    current = trusted_root
    for component in candidate.relative_to(trusted_root).parts:
        current = current / component
        try:
            metadata = os.lstat(current)
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(metadata.st_mode):
            raise ReleaseContractError(f"{label} contains symlink {current}.")
    return candidate


def _read_regular_file(path: Path, label: str) -> bytes:
    try:
        metadata = os.lstat(path)
    except FileNotFoundError as error:
        raise ReleaseContractError(f"{label} is missing.") from error
    if not stat.S_ISREG(metadata.st_mode):
        raise ReleaseContractError(f"{label} must be a regular file, not a symlink.")
    if metadata.st_nlink != 1:
        raise ReleaseContractError(f"{label} must not be a hard link.")
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise ReleaseContractError(f"{label} could not be opened safely.") from error
    with os.fdopen(descriptor, "rb", closefd=True) as handle:
        return handle.read()


def release_attestation_path(root: Path, source_sha: str) -> Path:
    sha = _validated_sha(source_sha, "Release attestation source SHA")
    attestation_root = _fixed_directory(
        root,
        Path(".build/release-attestations"),
        "Release attestation directory",
    )
    return attestation_root / f"{sha}.json"


def _pairs_without_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReleaseContractError(
                f"Release attestation contains duplicate key {key!r}."
            )
        result[key] = value
    return result


def validate_attestation_bytes(data: bytes, source: ReleaseSource) -> str:
    try:
        decoded = json.loads(
            data.decode("utf-8"), object_pairs_hook=_pairs_without_duplicates
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseContractError("Release attestation is not valid UTF-8 JSON.") from error
    expected = json.loads(canonical_attestation_bytes(source).decode("utf-8"))
    if decoded != expected:
        raise ReleaseContractError(
            "Release attestation schema, source SHA, tag, or gate result is invalid."
        )
    canonical = canonical_attestation_bytes(source)
    if data != canonical:
        raise ReleaseContractError(
            "Release attestation bytes are not in the canonical schema encoding."
        )
    return hashlib.sha256(data).hexdigest()


def _atomic_write(path: Path, data: bytes, allowed_root: Path) -> None:
    path = _require_physical_ancestry(path, allowed_root, "Release output path")
    parent = _require_physical_ancestry(
        path.parent, allowed_root, "Release output parent"
    )
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=parent
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
        file_descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            os.fsync(file_descriptor)
        finally:
            os.close(file_descriptor)
        parent_descriptor = os.open(
            parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        )
        try:
            os.fsync(parent_descriptor)
        finally:
            os.close(parent_descriptor)
    finally:
        temporary_path.unlink(missing_ok=True)


def _validated_gate_owner_pid(owner_pid: int | None) -> int:
    owner = owner_pid if owner_pid is not None else os.getppid()
    if owner <= 1:
        raise ReleaseContractError("Release gate owner PID is invalid.")
    try:
        owner_group = os.getpgid(owner)
    except ProcessLookupError as error:
        raise ReleaseContractError("Release gate owner process no longer exists.") from error
    if owner_group != os.getpgrp():
        raise ReleaseContractError(
            "Release gate owner must belong to the current process group."
        )
    return owner


def gate_begin(
    root: Path = ROOT,
    gate_owner_pid: int | None = None,
) -> ReleasePreflight:
    source = validate_release_source(root)
    owner_pid = _validated_gate_owner_pid(gate_owner_pid)
    attestation_root = _fixed_directory(
        root,
        Path(".build/release-attestations"),
        "Release attestation directory",
        create=True,
    )
    path = attestation_root / f"{source.sha}.json"
    try:
        metadata = os.lstat(path)
    except FileNotFoundError:
        pass
    else:
        if not stat.S_ISREG(metadata.st_mode):
            raise ReleaseContractError(
                "Existing release attestation must be a regular file."
            )
        path.unlink()
    gate_session = secrets.token_hex(32)
    gate_session_digest = hashlib.sha256(gate_session.encode("ascii")).hexdigest()
    session_root = _fixed_directory(
        root,
        Path(".build/release-attestations/sessions"),
        "Release gate session directory",
        create=True,
    )
    session_path = session_root / f"{gate_session_digest}.json"
    session_data = {
        "ownerPID": owner_pid,
        "schemaVersion": GATE_SESSION_SCHEMA_VERSION,
        "source": {"gitSHA": source.sha, "tag": source.tag},
        "tokenSHA256": gate_session_digest,
    }
    session_bytes = (
        json.dumps(session_data, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode("utf-8")
    _atomic_write(session_path, session_bytes, session_root)
    return ReleasePreflight(
        source=source,
        attestation_path=path,
        attestation_sha256="",
        gate_session=gate_session,
    )


def gate_complete(
    root: Path,
    source_sha: str,
    gate_session: str,
    gate_receipts: list[str],
    gate_owner_pid: int | None = None,
) -> Path:
    if GATE_SESSION_PATTERN.fullmatch(gate_session) is None:
        raise ReleaseContractError("Gate completion requires a valid one-use session.")
    receipt_set = set(gate_receipts)
    if len(receipt_set) != len(gate_receipts) or receipt_set != REQUIRED_GATE_RECEIPTS:
        missing = sorted(REQUIRED_GATE_RECEIPTS - receipt_set)
        unexpected = sorted(receipt_set - REQUIRED_GATE_RECEIPTS)
        raise ReleaseContractError(
            "Gate completion requires each explicit verification receipt exactly once; "
            f"missing={missing}, unexpected={unexpected}."
        )
    source = validate_release_source(root, expect_sha=source_sha)
    owner_pid = _validated_gate_owner_pid(gate_owner_pid)
    session_digest = hashlib.sha256(gate_session.encode("ascii")).hexdigest()
    session_root = _fixed_directory(
        root,
        Path(".build/release-attestations/sessions"),
        "Release gate session directory",
    )
    session_path = session_root / f"{session_digest}.json"
    session_bytes = _read_regular_file(session_path, "Release gate session")
    expected_session = {
        "ownerPID": owner_pid,
        "schemaVersion": GATE_SESSION_SCHEMA_VERSION,
        "source": {"gitSHA": source.sha, "tag": source.tag},
        "tokenSHA256": session_digest,
    }
    expected_session_bytes = (
        json.dumps(expected_session, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode("utf-8")
    if session_bytes != expected_session_bytes:
        raise ReleaseContractError(
            "Release gate session is stale, belongs to another parent/gate owner, "
            "or does not match the captured source."
        )
    try:
        session_path.unlink()
    except FileNotFoundError as error:
        raise ReleaseContractError(
            "Release gate session was already consumed."
        ) from error
    session_directory_descriptor = os.open(
        session_root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    )
    try:
        os.fsync(session_directory_descriptor)
    finally:
        os.close(session_directory_descriptor)
    data = canonical_attestation_bytes(source)
    attestation_root = _fixed_directory(
        root,
        Path(".build/release-attestations"),
        "Release attestation directory",
        create=True,
    )
    path = attestation_root / f"{source.sha}.json"
    _atomic_write(path, data, attestation_root)
    validate_attestation_bytes(_read_regular_file(path, "Release attestation"), source)
    return path


def release_output_paths(
    root: Path,
    release_mode: str,
    *,
    validate_destinations: bool = True,
) -> dict[str, Path]:
    if release_mode not in {"local", "public"}:
        raise ReleaseContractError("Release mode must be exactly local or public.")
    values = environment_values(root)
    trusted_root = root.resolve()
    archive_parent = _fixed_directory(
        trusted_root,
        Path(".build") / "Release" / release_mode,
        "Release archive directory",
    )
    archive_path = _require_physical_ancestry(
        archive_parent / "Cadence.xcarchive",
        archive_parent,
        "Release archive path",
    )
    output_dir = _fixed_directory(
        trusted_root,
        Path(".build")
        / "releases"
        / release_mode
        / values["PUBLIC_VERSION"],
        "Release artifact output directory",
    )
    paths = {
        "RELEASE_ARCHIVE_PATH": archive_path,
        "RELEASE_OUTPUT_DIR": output_dir,
        "RELEASE_DMG_PATH": _require_physical_ancestry(
            output_dir / values["DMG_NAME"], output_dir, "Release DMG path"
        ),
        "RELEASE_ZIP_PATH": _require_physical_ancestry(
            output_dir / values["ZIP_NAME"], output_dir, "Release ZIP path"
        ),
        "RELEASE_CHECKSUMS_PATH": _require_physical_ancestry(
            output_dir / values["CHECKSUMS_NAME"],
            output_dir,
            "Release checksums path",
        ),
    }
    if validate_destinations:
        _validate_artifact_destination(paths["RELEASE_DMG_PATH"], "Release DMG path")
        _validate_artifact_destination(paths["RELEASE_ZIP_PATH"], "Release ZIP path")
        _validate_artifact_destination(
            paths["RELEASE_CHECKSUMS_PATH"], "Release checksums path"
        )
    return paths


def _validate_artifact_destination(path: Path, label: str) -> None:
    try:
        metadata = os.lstat(path)
    except FileNotFoundError:
        return
    if not stat.S_ISREG(metadata.st_mode):
        raise ReleaseContractError(f"{label} must be absent or a regular file.")
    if metadata.st_nlink != 1:
        raise ReleaseContractError(f"{label} must not be a hard link.")


def _release_operation_relative_directories(
    root: Path, release_mode: str
) -> tuple[Path, ...]:
    values = environment_values(root)
    return (
        Path(".build"),
        Path(".build/Release"),
        Path(".build/Release") / release_mode,
        Path(".build/releases"),
        Path(".build/releases") / release_mode,
        Path(".build/releases") / release_mode / values["PUBLIC_VERSION"],
    )


def _release_operation_directories(root: Path, release_mode: str) -> list[Path]:
    return [
        _fixed_directory(
            root,
            relative,
            "Release operation directory",
            create=True,
        )
        for relative in _release_operation_relative_directories(root, release_mode)
    ]


def _directory_identity(root: Path, path: Path) -> dict[str, Any]:
    metadata = os.lstat(path)
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise ReleaseContractError(
            f"Release operation path identity is not a physical directory: {path}."
        )
    return {
        "device": metadata.st_dev,
        "inode": metadata.st_ino,
        "path": path.relative_to(root.resolve()).as_posix(),
    }


def _operation_manifest_bytes(data: dict[str, Any]) -> bytes:
    return (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode(
        "utf-8"
    )


def _release_contract_sha256(root: Path) -> str:
    return hashlib.sha256(
        _read_regular_file(root.resolve() / "release-contract.json", "Release contract")
    ).hexdigest()


def _operation_outputs(root: Path, release_mode: str) -> dict[str, str]:
    values = environment_values(root)
    archive = Path(".build") / "Release" / release_mode / "Cadence.xcarchive"
    output = (
        Path(".build")
        / "releases"
        / release_mode
        / values["PUBLIC_VERSION"]
    )
    return {
        "RELEASE_ARCHIVE_PATH": archive.as_posix(),
        "RELEASE_OUTPUT_DIR": output.as_posix(),
        "RELEASE_DMG_PATH": (output / values["DMG_NAME"]).as_posix(),
        "RELEASE_ZIP_PATH": (output / values["ZIP_NAME"]).as_posix(),
        "RELEASE_CHECKSUMS_PATH": (output / values["CHECKSUMS_NAME"]).as_posix(),
    }


def _process_identity(process_id: int) -> dict[str, Any] | None:
    try:
        process_group = os.getpgid(process_id)
    except ProcessLookupError:
        return None
    except PermissionError as error:
        raise ReleaseContractError(
            "Release operation owner identity could not be inspected."
        ) from error
    start_time = _process_start_identity(process_id)
    if start_time is None:
        return None
    if not start_time:
        raise ReleaseContractError(
            "Release operation owner start identity could not be inspected; "
            "the lock must fail closed."
        )
    return {
        "pid": process_id,
        "processGroup": process_group,
        "startTime": start_time,
    }


def _process_start_identity(process_id: int) -> str | None:
    if sys.platform == "darwin":
        class ProcessBSDInfo(ctypes.Structure):
            _fields_ = [
                ("flags", ctypes.c_uint32),
                ("status", ctypes.c_uint32),
                ("xstatus", ctypes.c_uint32),
                ("pid", ctypes.c_uint32),
                ("ppid", ctypes.c_uint32),
                ("uid", ctypes.c_uint32),
                ("gid", ctypes.c_uint32),
                ("ruid", ctypes.c_uint32),
                ("rgid", ctypes.c_uint32),
                ("svuid", ctypes.c_uint32),
                ("svgid", ctypes.c_uint32),
                ("reserved", ctypes.c_uint32),
                ("command", ctypes.c_char * 16),
                ("name", ctypes.c_char * 32),
                ("openFiles", ctypes.c_uint32),
                ("processGroup", ctypes.c_uint32),
                ("jobControl", ctypes.c_uint32),
                ("terminalDevice", ctypes.c_uint32),
                ("terminalProcessGroup", ctypes.c_uint32),
                ("nice", ctypes.c_int32),
                ("startSeconds", ctypes.c_uint64),
                ("startMicroseconds", ctypes.c_uint64),
            ]

        library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        proc_pidinfo = library.proc_pidinfo
        proc_pidinfo.argtypes = [
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_uint64,
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        proc_pidinfo.restype = ctypes.c_int
        process_info = ProcessBSDInfo()
        ctypes.set_errno(0)
        received = proc_pidinfo(
            process_id,
            3,
            0,
            ctypes.byref(process_info),
            ctypes.sizeof(process_info),
        )
        if received == ctypes.sizeof(process_info):
            return (
                f"darwin:{process_info.startSeconds}:"
                f"{process_info.startMicroseconds}"
            )
        if ctypes.get_errno() == errno.ESRCH:
            return None
        raise ReleaseContractError(
            "Release operation owner start identity could not be inspected; "
            "the lock must fail closed."
        )
    if sys.platform.startswith("linux"):
        try:
            stat_fields = Path(f"/proc/{process_id}/stat").read_text(
                encoding="ascii"
            )
        except FileNotFoundError:
            return None
        except (OSError, UnicodeDecodeError) as error:
            raise ReleaseContractError(
                "Release operation owner start identity could not be inspected; "
                "the lock must fail closed."
            ) from error
        closing_parenthesis = stat_fields.rfind(")")
        remaining = stat_fields[closing_parenthesis + 2 :].split()
        if closing_parenthesis < 0 or len(remaining) <= 19:
            raise ReleaseContractError(
                "Release operation owner start identity is malformed."
            )
        return f"linux:{remaining[19]}"
    raise ReleaseContractError(
        "This platform cannot prove release operation process start identity."
    )


def _validated_operation_owner(owner_pid: int | None) -> dict[str, Any]:
    if owner_pid is None:
        raise ReleaseContractError(
            "Release operation owner PID must be supplied explicitly."
        )
    process_id = owner_pid
    if process_id <= 1:
        raise ReleaseContractError("Release operation owner PID is invalid.")
    identity = _process_identity(process_id)
    if identity is None:
        raise ReleaseContractError("Release operation owner process no longer exists.")
    if identity["pid"] != identity["processGroup"]:
        raise ReleaseContractError(
            "Release operation owner must lead its dedicated process group."
        )
    return identity


def _operation_payload_hmac(operation_token: str, payload: dict[str, Any]) -> str:
    return hmac.new(
        bytes.fromhex(operation_token),
        _operation_manifest_bytes(payload),
        hashlib.sha256,
    ).hexdigest()


def _decode_operation_manifest(
    data: bytes,
    expected_release_mode: str | None = None,
) -> dict[str, Any]:
    try:
        manifest = json.loads(
            data.decode("utf-8"), object_pairs_hook=_pairs_without_duplicates
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseContractError("Release operation manifest is invalid.") from error
    if not isinstance(manifest, dict):
        raise ReleaseContractError("Release operation manifest is invalid.")
    expected_keys = {
        "directories",
        "fullGateAttestationSHA256",
        "outputs",
        "owner",
        "payloadHMAC",
        "releaseContractSHA256",
        "releaseMode",
        "schemaVersion",
        "source",
    }
    if set(manifest) != expected_keys:
        raise ReleaseContractError(
            "Release operation manifest does not have the exact schema."
        )
    release_mode = manifest.get("releaseMode")
    if (
        manifest.get("schemaVersion") != RELEASE_OPERATION_SCHEMA_VERSION
        or release_mode not in {"local", "public"}
        or (
            expected_release_mode is not None
            and release_mode != expected_release_mode
        )
    ):
        raise ReleaseContractError(
            "Release operation manifest schema or mode does not match."
        )
    for digest_key in (
        "fullGateAttestationSHA256",
        "payloadHMAC",
        "releaseContractSHA256",
    ):
        value = manifest.get(digest_key)
        if not isinstance(value, str) or GATE_SESSION_PATTERN.fullmatch(value) is None:
            raise ReleaseContractError(
                f"Release operation manifest {digest_key} is invalid."
            )

    source = manifest.get("source")
    if not isinstance(source, dict) or set(source) != {"gitSHA", "tag"}:
        raise ReleaseContractError("Release operation manifest source is invalid.")
    if (
        not isinstance(source.get("gitSHA"), str)
        or SHA_PATTERN.fullmatch(source["gitSHA"]) is None
        or not isinstance(source.get("tag"), str)
        or not source["tag"]
        or "\n" in source["tag"]
        or "\r" in source["tag"]
    ):
        raise ReleaseContractError("Release operation manifest source is invalid.")

    owner = manifest.get("owner")
    if not isinstance(owner, dict) or set(owner) != {
        "pid",
        "processGroup",
        "startTime",
    }:
        raise ReleaseContractError("Release operation manifest owner is invalid.")
    if (
        not isinstance(owner.get("pid"), int)
        or isinstance(owner["pid"], bool)
        or owner["pid"] <= 1
        or not isinstance(owner.get("processGroup"), int)
        or isinstance(owner["processGroup"], bool)
        or owner["processGroup"] <= 0
        or not isinstance(owner.get("startTime"), str)
        or not owner["startTime"]
        or "\n" in owner["startTime"]
        or "\r" in owner["startTime"]
        or owner["pid"] != owner["processGroup"]
    ):
        raise ReleaseContractError("Release operation manifest owner is invalid.")

    outputs = manifest.get("outputs")
    expected_output_keys = {
        "RELEASE_ARCHIVE_PATH",
        "RELEASE_CHECKSUMS_PATH",
        "RELEASE_DMG_PATH",
        "RELEASE_OUTPUT_DIR",
        "RELEASE_ZIP_PATH",
    }
    if not isinstance(outputs, dict) or set(outputs) != expected_output_keys:
        raise ReleaseContractError(
            "Release operation manifest output path set is invalid."
        )
    if any(not isinstance(value, str) for value in outputs.values()):
        raise ReleaseContractError(
            "Release operation manifest output path set is invalid."
        )
    archive_path = Path(outputs["RELEASE_ARCHIVE_PATH"])
    output_directory = Path(outputs["RELEASE_OUTPUT_DIR"])
    expected_archive = (
        Path(".build") / "Release" / release_mode / "Cadence.xcarchive"
    )
    output_parts = output_directory.parts
    if (
        archive_path != expected_archive
        or outputs["RELEASE_ARCHIVE_PATH"] != expected_archive.as_posix()
        or archive_path.is_absolute()
        or output_directory.is_absolute()
        or outputs["RELEASE_OUTPUT_DIR"] != output_directory.as_posix()
        or len(output_parts) != 4
        or output_parts[:3] != (".build", "releases", release_mode)
        or output_parts[3] in {"", ".", ".."}
        or SAFE_COMPONENT_PATTERN.fullmatch(output_parts[3]) is None
    ):
        raise ReleaseContractError(
            "Release operation manifest output paths are not exact contained paths."
        )
    artifact_contract = (
        ("RELEASE_DMG_PATH", ".dmg"),
        ("RELEASE_ZIP_PATH", ".zip"),
        ("RELEASE_CHECKSUMS_PATH", "-SHA256SUMS.txt"),
    )
    for output_key, suffix in artifact_contract:
        artifact_path = Path(outputs[output_key])
        if (
            artifact_path.is_absolute()
            or outputs[output_key] != artifact_path.as_posix()
            or artifact_path.parent != output_directory
            or artifact_path.name in {"", ".", ".."}
            or SAFE_COMPONENT_PATTERN.fullmatch(artifact_path.name) is None
            or not artifact_path.name.endswith(suffix)
        ):
            raise ReleaseContractError(
                "Release operation manifest output paths are not exact contained paths."
            )

    directories = manifest.get("directories")
    expected_directory_paths = [
        ".build",
        ".build/Release",
        f".build/Release/{release_mode}",
        ".build/releases",
        f".build/releases/{release_mode}",
        output_directory.as_posix(),
    ]
    if not isinstance(directories, list) or len(directories) != len(
        expected_directory_paths
    ):
        raise ReleaseContractError(
            "Release operation manifest directory set is invalid."
        )
    actual_directory_paths: list[str] = []
    for identity in directories:
        if not isinstance(identity, dict) or set(identity) != {
            "device",
            "inode",
            "path",
        }:
            raise ReleaseContractError(
                "Release operation manifest directory identity is invalid."
            )
        if (
            not isinstance(identity.get("device"), int)
            or isinstance(identity["device"], bool)
            or identity["device"] < 0
            or not isinstance(identity.get("inode"), int)
            or isinstance(identity["inode"], bool)
            or identity["inode"] <= 0
            or not isinstance(identity.get("path"), str)
        ):
            raise ReleaseContractError(
                "Release operation manifest directory identity is invalid."
            )
        actual_directory_paths.append(identity["path"])
    if actual_directory_paths != expected_directory_paths:
        raise ReleaseContractError(
            "Release operation manifest directory path set is invalid."
        )
    if _operation_manifest_bytes(manifest) != data:
        raise ReleaseContractError("Release operation manifest is not canonical.")
    return manifest


def _require_recorded_operation_group_absent(owner: dict[str, Any]) -> None:
    current_identity = _process_identity(owner["pid"])
    if current_identity == owner:
        raise ReleaseContractError(
            "Another release operation is already active; its live owner "
            "cannot be replaced."
        )
    if current_identity is not None:
        raise ReleaseContractError(
            "The recorded release owner PID or process group was reused; "
            "automatic recovery must fail closed."
        )
    try:
        os.killpg(owner["processGroup"], 0)
    except ProcessLookupError:
        return
    except PermissionError as error:
        raise ReleaseContractError(
            "The recorded release process group cannot be inspected; "
            "automatic recovery must fail closed."
        ) from error
    except OSError as error:
        raise ReleaseContractError(
            "The recorded release process group has indeterminate state; "
            "automatic recovery must fail closed."
        ) from error
    raise ReleaseContractError(
        "The recorded release process group still has a live member; "
        "another operation cannot begin."
    )


def _recover_existing_operation_lock(root: Path) -> bool:
    trusted_root = root.resolve()
    lock_directory = _fixed_directory(
        trusted_root,
        RELEASE_OPERATION_RELATIVE_PATH,
        "Release operation lock",
    )
    try:
        lock_before = os.lstat(lock_directory)
        data = _read_regular_file(
            lock_directory / "operation.json", "Release operation manifest"
        )
        manifest_before = os.lstat(lock_directory / "operation.json")
        manifest = _decode_operation_manifest(data)
    except (OSError, ReleaseContractError) as error:
        raise ReleaseContractError(
            "Release operation lock is malformed or incomplete; it was not "
            "removed automatically. Inspect it and recover it explicitly."
        ) from error
    recorded_owner = manifest["owner"]
    _require_recorded_operation_group_absent(recorded_owner)

    build_root = trusted_root / ".build"
    quarantine = build_root / (
        f".cadence-release-operation.stale.{secrets.token_hex(16)}"
    )
    if sorted(os.listdir(lock_directory)) != ["operation.json"]:
        raise ReleaseContractError(
            "Release operation lock contains unexpected state; it was not "
            "removed automatically. Inspect it and recover it explicitly."
        )
    try:
        os.rename(lock_directory, quarantine)
    except OSError as error:
        raise ReleaseContractError(
            "Release operation lock changed during stale-owner recovery."
        ) from error
    try:
        lock_after = os.lstat(quarantine)
        manifest_after = os.lstat(quarantine / "operation.json")
        after_data = _read_regular_file(
            quarantine / "operation.json", "Release operation manifest"
        )
        if (
            lock_after.st_dev != lock_before.st_dev
            or lock_after.st_ino != lock_before.st_ino
            or manifest_after.st_dev != manifest_before.st_dev
            or manifest_after.st_ino != manifest_before.st_ino
            or after_data != data
        ):
            raise ReleaseContractError(
                "Release operation owner or lock identity changed during recovery."
            )
        _require_recorded_operation_group_absent(recorded_owner)
        (quarantine / "operation.json").unlink()
        quarantine.rmdir()
        build_descriptor = os.open(
            build_root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        )
        try:
            os.fsync(build_descriptor)
        finally:
            os.close(build_descriptor)
    except Exception:
        if quarantine.exists() and not lock_directory.exists():
            try:
                os.rename(quarantine, lock_directory)
            except OSError:
                pass
        raise
    return True


def _publish_operation_manifest(
    build_root: Path,
    lock_directory: Path,
    data: bytes,
) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".cadence-release-operation.", suffix=".json", dir=build_root
    )
    temporary_path = Path(temporary_name)
    lock_created = False
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        lock_directory.mkdir(mode=0o700)
        lock_created = True
        os.link(temporary_path, lock_directory / "operation.json")
        temporary_path.unlink()
        lock_descriptor = os.open(
            lock_directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        )
        try:
            os.fsync(lock_descriptor)
        finally:
            os.close(lock_descriptor)
        build_descriptor = os.open(
            build_root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        )
        try:
            os.fsync(build_descriptor)
        finally:
            os.close(build_descriptor)
    except FileExistsError:
        raise
    except OSError as error:
        if lock_created:
            raise ReleaseContractError(
                "Release operation owner evidence could not be published; the "
                "incomplete fail-closed lock requires explicit recovery."
            ) from error
        raise ReleaseContractError(
            "Release operation manifest could not be prepared safely."
        ) from error
    finally:
        temporary_path.unlink(missing_ok=True)


def release_operation_begin(
    root: Path,
    release_mode: str,
    expect_sha: str | None,
    operation_owner_pid: int | None = None,
    operation_token: str | None = None,
) -> tuple[str, dict[str, Path]]:
    trusted_root = root.resolve()
    build_root = _fixed_directory(
        trusted_root, Path(".build"), "Release operation root", create=True
    )
    lock_directory = trusted_root / RELEASE_OPERATION_RELATIVE_PATH
    recovered_stale_lock = False
    for attempt in range(2):
        if lock_directory.exists() or lock_directory.is_symlink():
            recovered_stale_lock = _recover_existing_operation_lock(trusted_root)
        preflight = release_preflight(trusted_root, expect_sha=expect_sha)
        owner = _validated_operation_owner(operation_owner_pid)
        if operation_token is None:
            operation_token = secrets.token_hex(32)
        elif GATE_SESSION_PATTERN.fullmatch(operation_token) is None:
            raise ReleaseContractError("Release operation token is invalid.")
        directories = _release_operation_directories(trusted_root, release_mode)
        payload = {
            "directories": [
                _directory_identity(trusted_root, path) for path in directories
            ],
            "fullGateAttestationSHA256": preflight.attestation_sha256,
            "outputs": _operation_outputs(trusted_root, release_mode),
            "owner": owner,
            "releaseContractSHA256": _release_contract_sha256(trusted_root),
            "releaseMode": release_mode,
            "schemaVersion": RELEASE_OPERATION_SCHEMA_VERSION,
            "source": {
                "gitSHA": preflight.source.sha,
                "tag": preflight.source.tag,
            },
        }
        manifest = {
            **payload,
            "payloadHMAC": _operation_payload_hmac(operation_token, payload),
        }
        try:
            _publish_operation_manifest(
                build_root,
                lock_directory,
                _operation_manifest_bytes(manifest),
            )
        except FileExistsError:
            if attempt == 0:
                continue
            raise ReleaseContractError(
                "Another release operation won the lock publication race."
            )
        if recovered_stale_lock:
            print(
                "Recovered stale release operation after confirming its recorded "
                "owner and process group exited.",
                file=sys.stderr,
            )
        return operation_token, release_output_paths(trusted_root, release_mode)
    raise ReleaseContractError("Release operation lock could not be acquired safely.")


def _load_authenticated_release_operation(
    root: Path,
    release_mode: str,
    operation_token: str,
) -> tuple[Path, dict[str, Any]]:
    if GATE_SESSION_PATTERN.fullmatch(operation_token) is None:
        raise ReleaseContractError("Release operation token is invalid.")
    trusted_root = root.resolve()
    lock_directory = _fixed_directory(
        trusted_root,
        RELEASE_OPERATION_RELATIVE_PATH,
        "Release operation lock",
    )
    manifest_path = lock_directory / "operation.json"
    data = _read_regular_file(manifest_path, "Release operation manifest")
    manifest = _decode_operation_manifest(data, release_mode)
    payload = {key: value for key, value in manifest.items() if key != "payloadHMAC"}
    expected_hmac = _operation_payload_hmac(operation_token, payload)
    if not hmac.compare_digest(manifest["payloadHMAC"], expected_hmac):
        raise ReleaseContractError(
            "Release operation token does not authenticate the exact manifest."
        )
    return lock_directory, manifest


def _load_release_operation(
    root: Path,
    release_mode: str,
    operation_token: str,
    *,
    validate_directories: bool,
    validate_artifacts: bool = True,
    validate_source: bool = True,
    operation_owner_pid: int | None = None,
) -> tuple[Path, dict[str, Any]]:
    trusted_root = root.resolve()
    lock_directory, manifest = _load_authenticated_release_operation(
        trusted_root, release_mode, operation_token
    )
    owner = _validated_operation_owner(operation_owner_pid)
    if owner != manifest["owner"]:
        raise ReleaseContractError(
            "Release operation belongs to a different owner identity."
        )
    if validate_source:
        if _release_contract_sha256(trusted_root) != manifest["releaseContractSHA256"]:
            raise ReleaseContractError(
                "Release contract changed after the operation began."
            )
        if _operation_outputs(trusted_root, release_mode) != manifest["outputs"]:
            raise ReleaseContractError(
                "Release output contract changed after the operation began."
            )
        preflight = release_preflight(
            trusted_root, expect_sha=manifest["source"]["gitSHA"]
        )
        if (
            preflight.source.tag != manifest["source"]["tag"]
            or preflight.attestation_sha256
            != manifest["fullGateAttestationSHA256"]
        ):
            raise ReleaseContractError(
                "Release source, tag, or gate evidence changed after operation begin."
            )
    if validate_directories:
        try:
            for identity in manifest["directories"]:
                path = trusted_root / str(identity["path"])
                if _directory_identity(trusted_root, path) != identity:
                    raise ReleaseContractError(
                        f"Release operation path identity changed: {path}."
                    )
            release_output_paths(
                trusted_root,
                release_mode,
                validate_destinations=validate_artifacts,
            )
        except (KeyError, TypeError, OSError, ReleaseContractError) as error:
            raise ReleaseContractError(
                f"Release operation path identity changed: {error}."
            ) from error
    return lock_directory, manifest


def release_operation_check(
    root: Path,
    release_mode: str,
    operation_token: str,
    operation_owner_pid: int | None = None,
) -> None:
    _load_release_operation(
        root,
        release_mode,
        operation_token,
        validate_directories=True,
        operation_owner_pid=operation_owner_pid,
    )


def release_operation_end(
    root: Path,
    release_mode: str,
    operation_token: str,
    expected_owner: dict[str, Any] | None = None,
) -> None:
    lock_directory, manifest = _load_authenticated_release_operation(
        root, release_mode, operation_token
    )
    recorded_owner = manifest["owner"]
    if expected_owner is not None and recorded_owner != expected_owner:
        raise ReleaseContractError(
            "Release operation owner changed before supervised finalization."
        )
    _require_recorded_operation_group_absent(recorded_owner)
    if sorted(os.listdir(lock_directory)) != ["operation.json"]:
        raise ReleaseContractError(
            "Release operation lock contains unexpected state and was not finalized."
        )
    manifest_path = lock_directory / "operation.json"
    manifest_path.unlink()
    lock_directory.rmdir()
    build_descriptor = os.open(
        lock_directory.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    )
    try:
        os.fsync(build_descriptor)
    finally:
        os.close(build_descriptor)


def _sha256_regular_file(path: Path, label: str) -> str:
    try:
        before = os.lstat(path)
    except FileNotFoundError as error:
        raise ReleaseContractError(f"{label} is missing.") from error
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ReleaseContractError(
            f"{label} must be one single-link regular file before checksumming."
        )
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise ReleaseContractError(f"{label} could not be opened safely.") from error
    digest = hashlib.sha256()
    with os.fdopen(descriptor, "rb", closefd=True) as handle:
        opened = os.fstat(handle.fileno())
        if (
            opened.st_dev != before.st_dev
            or opened.st_ino != before.st_ino
            or not stat.S_ISREG(opened.st_mode)
            or opened.st_nlink != 1
        ):
            raise ReleaseContractError(f"{label} changed while it was opened.")
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def release_checksums_write(
    root: Path,
    release_mode: str,
    operation_token: str,
    operation_owner_pid: int | None = None,
) -> Path:
    trusted_root = root.resolve()
    _, operation = _load_release_operation(
        trusted_root,
        release_mode,
        operation_token,
        validate_directories=True,
        validate_artifacts=False,
        operation_owner_pid=operation_owner_pid,
    )
    paths = release_output_paths(
        trusted_root,
        release_mode,
        validate_destinations=False,
    )
    dmg_path = paths["RELEASE_DMG_PATH"]
    zip_path = paths["RELEASE_ZIP_PATH"]
    checksum_path = paths["RELEASE_CHECKSUMS_PATH"]
    checksum_data = (
        f"{_sha256_regular_file(dmg_path, 'Release DMG')}  {dmg_path.name}\n"
        f"{_sha256_regular_file(zip_path, 'Release ZIP')}  {zip_path.name}\n"
    ).encode("ascii")

    output_directory = checksum_path.parent
    relative_output = output_directory.relative_to(trusted_root).as_posix()
    expected_identity = next(
        (
            identity
            for identity in operation.get("directories", [])
            if isinstance(identity, dict) and identity.get("path") == relative_output
        ),
        None,
    )
    if expected_identity is None:
        raise ReleaseContractError(
            "Release operation does not own the checksums output directory."
        )
    try:
        directory_descriptor = os.open(
            output_directory,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
    except OSError as error:
        raise ReleaseContractError(
            "Checksums output directory could not be opened safely."
        ) from error
    temporary_name = f".{checksum_path.name}.{secrets.token_hex(12)}.tmp"
    try:
        opened = os.fstat(directory_descriptor)
        opened_identity = {
            "device": opened.st_dev,
            "inode": opened.st_ino,
            "path": relative_output,
        }
        if opened_identity != expected_identity:
            raise ReleaseContractError(
                "Release operation checksums directory identity changed."
            )
        temporary_descriptor = os.open(
            temporary_name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o644,
            dir_fd=directory_descriptor,
        )
        try:
            with os.fdopen(temporary_descriptor, "wb", closefd=True) as handle:
                handle.write(checksum_data)
                handle.flush()
                os.fsync(handle.fileno())
        except Exception:
            try:
                os.close(temporary_descriptor)
            except OSError:
                pass
            raise
        os.rename(
            temporary_name,
            checksum_path.name,
            src_dir_fd=directory_descriptor,
            dst_dir_fd=directory_descriptor,
        )
        os.fsync(directory_descriptor)
    except OSError as error:
        raise ReleaseContractError("Checksums could not be written safely.") from error
    finally:
        try:
            os.unlink(temporary_name, dir_fd=directory_descriptor)
        except FileNotFoundError:
            pass
        os.close(directory_descriptor)
    _validate_artifact_destination(checksum_path, "Release checksums path")
    return checksum_path


def release_preflight(
    root: Path = ROOT,
    expect_sha: str | None = None,
) -> ReleasePreflight:
    source = validate_release_source(root, expect_sha=expect_sha)
    path = release_attestation_path(root, source.sha)
    try:
        data = _read_regular_file(path, "Full-gate attestation")
    except ReleaseContractError as error:
        raise ReleaseContractError(
            f"Full-gate attestation is missing for {source.sha}; run "
            "scripts/verify.sh --release-attestation on this clean tagged commit."
        ) from error
    digest = validate_attestation_bytes(data, source)
    return ReleasePreflight(
        source=source,
        attestation_path=path,
        attestation_sha256=digest,
    )


def validate_release_notes_path(
    root: Path,
    requested_path: Path,
    source: ReleaseSource,
) -> Path:
    lexical_root = Path(os.path.abspath(root))
    trusted_root = root.resolve()
    release_root = _fixed_directory(
        trusted_root,
        Path("release"),
        "Release notes root",
    )
    requested_absolute = Path(os.path.abspath(requested_path))
    relative_candidate: Path | None = None
    try:
        relative_candidate = requested_absolute.relative_to(lexical_root)
    except ValueError:
        try:
            relative_candidate = requested_absolute.relative_to(trusted_root)
        except ValueError:
            for possible_root in requested_absolute.parents:
                try:
                    same_repository = os.path.samefile(possible_root, trusted_root)
                except OSError:
                    continue
                if same_repository:
                    relative_candidate = requested_absolute.relative_to(possible_root)
                    break
    if relative_candidate is None:
        raise ReleaseContractError(
            "Release notes path is outside the repository release directory: "
            f"{requested_absolute}."
        )
    candidate = _require_physical_ancestry(
        trusted_root / relative_candidate,
        release_root,
        "Release notes path",
    )
    relative = candidate.relative_to(trusted_root).as_posix()
    tagged_entry = _parse_git_tree(
        _run_git(
            trusted_root,
            "ls-tree",
            "-r",
            "-z",
            "--full-tree",
            source.sha,
            "--",
            relative,
        )
    )
    index_entry = _parse_git_index(
        _run_git(trusted_root, "ls-files", "--stage", "-z", "--", relative)
    )
    if set(tagged_entry) != {relative} or index_entry != tagged_entry:
        raise ReleaseContractError(
            "Release notes must be one tracked file from the exact tagged source."
        )
    expected_mode, expected_oid = tagged_entry[relative]
    actual_oid = _raw_worktree_blob_oid(candidate, expected_mode, relative)
    if actual_oid != expected_oid:
        raise ReleaseContractError(
            "Release notes do not match their exact tagged Git blob."
        )
    return candidate


def _archive_path(root: Path, archive: Path) -> Path:
    lexical_root = Path(os.path.abspath(root))
    trusted_root = root.resolve()
    release_root = _fixed_directory(
        trusted_root,
        Path(".build/Release"),
        "Release root",
    )
    lexical_archive = Path(os.path.abspath(archive))
    try:
        relative_archive = lexical_archive.relative_to(lexical_root)
    except ValueError:
        try:
            relative_archive = lexical_archive.relative_to(trusted_root)
        except ValueError:
            raise ReleaseContractError(
                "Archive path is outside the allowed release directory: "
                f"{lexical_archive}."
            ) from None
    candidate = _require_physical_ancestry(
        trusted_root / relative_archive, release_root, "Archive path"
    )
    if candidate.suffix != ".xcarchive":
        raise ReleaseContractError("Archive path must name a .xcarchive directory.")
    return candidate


def _validate_archive_plist(archive: Path, preflight: ReleasePreflight) -> None:
    info_path = _require_physical_ancestry(
        archive
        / "Products"
        / "Applications"
        / "Cadence.app"
        / "Contents"
        / "Info.plist",
        archive,
        "Archive app Info.plist",
    )
    try:
        info = plistlib.loads(_read_regular_file(info_path, "Archive app Info.plist"))
    except (OSError, plistlib.InvalidFileException) as error:
        raise ReleaseContractError("Archive app Info.plist is invalid.") from error
    expected = {
        "CadenceSourceGitSHA": preflight.source.sha,
        "CadenceReleaseTag": preflight.source.tag,
        "CadenceFullGateAttestationSHA256": preflight.attestation_sha256,
    }
    for key, expected_value in expected.items():
        actual = info.get(key)
        if actual != expected_value:
            label = "source SHA" if key == "CadenceSourceGitSHA" else key
            raise ReleaseContractError(
                f"Archive {label} {actual!r} does not match release source "
                f"{expected_value!r}."
            )


def archive_stamp(root: Path, archive: Path, source_sha: str) -> Path:
    preflight = release_preflight(root, expect_sha=source_sha)
    archive = _archive_path(root, archive)
    _validate_archive_plist(archive, preflight)
    sidecar = archive / "CadenceReleaseAttestation.json"
    _atomic_write(
        sidecar,
        _read_regular_file(
            preflight.attestation_path, "Local full-gate attestation"
        ),
        archive,
    )
    return sidecar


def archive_check(root: Path, archive: Path, source_sha: str) -> None:
    preflight = release_preflight(root, expect_sha=source_sha)
    archive = _archive_path(root, archive)
    _validate_archive_plist(archive, preflight)
    sidecar = _require_physical_ancestry(
        archive / "CadenceReleaseAttestation.json",
        archive,
        "Archive release attestation",
    )
    archive_bytes = _read_regular_file(sidecar, "Archive full-gate attestation")
    local_bytes = _read_regular_file(
        preflight.attestation_path, "Local full-gate attestation"
    )
    if archive_bytes != local_bytes:
        raise ReleaseContractError(
            "Archive full-gate attestation does not match the current canonical evidence."
        )
    digest = validate_attestation_bytes(archive_bytes, preflight.source)
    if digest != preflight.attestation_sha256:
        raise ReleaseContractError(
            "Archive full-gate attestation digest does not match release evidence."
        )


def _safe_component(value: Any, label: str, suffix: str | None = None) -> str:
    component = str(value)
    if (
        component in {"", ".", ".."}
        or "/" in component
        or "\\" in component
        or SAFE_COMPONENT_PATTERN.fullmatch(component) is None
    ):
        raise ReleaseContractError(
            f"{label} must be one safe non-empty path component."
        )
    if suffix is not None and not component.endswith(suffix):
        raise ReleaseContractError(f"{label} must end with {suffix}.")
    return component


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
        "PUBLIC_VERSION": _safe_component(release["version"], "Release version"),
        "TAG": str(release["tag"]),
        "MINIMUM_MACOS": str(platform["minimumVersion"]),
        "ARCHITECTURE": str(platform["architecture"]),
        "DMG_NAME": _safe_component(
            artifacts["installer"], "Installer artifact name", ".dmg"
        ),
        "ZIP_NAME": _safe_component(
            artifacts["update"], "Update artifact name", ".zip"
        ),
        "CHECKSUMS_NAME": _safe_component(
            artifacts["checksums"], "Checksums artifact name", "-SHA256SUMS.txt"
        ),
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


def validate_public_release_environment(
    root: Path = ROOT,
    environment: dict[str, str] | os._Environ[str] = os.environ,
) -> list[str]:
    """Return every condition that makes a public build unsafe to publish."""
    data = load_manifest(root)
    distribution = data.get("distribution", {})
    errors: list[str] = []

    required_environment = (
        "CADENCE_DEVELOPER_ID_APPLICATION",
        "CADENCE_DEVELOPMENT_TEAM",
        "CADENCE_NOTARY_KEYCHAIN_PROFILE",
    )
    for key in required_environment:
        if not environment.get(key, "").strip():
            errors.append(f"{key} is required")

    if distribution.get("signing") != "developer-id":
        errors.append("distribution.signing must be developer-id")
    if distribution.get("notarized") is not True:
        errors.append("distribution.notarized must be true")
    if distribution.get("gatekeeperDisclosure") is not False:
        errors.append("distribution.gatekeeperDisclosure must be false")

    return errors


def _supervised_process_group_exists(process_group: int) -> bool:
    try:
        os.killpg(process_group, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # A permission denial still proves that the supervised group exists.
        # Keep waiting for it to drain instead of reporting it as absent or
        # aborting a release whose child processes are still accounted for.
        return True
    except OSError as error:
        raise ReleaseContractError(
            "The supervised release process group has indeterminate state."
        ) from error
    return True


def supervise_prepare(
    root: Path = ROOT,
    release_notes: Path | None = None,
) -> int:
    trusted_root = root.resolve()
    prepare_script = _require_physical_ancestry(
        trusted_root / "scripts" / "prepare_release.sh",
        trusted_root,
        "Release preparation script",
    )
    try:
        metadata = os.lstat(prepare_script)
    except FileNotFoundError as error:
        raise ReleaseContractError("Release preparation script is missing.") from error
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        raise ReleaseContractError(
            "Release preparation script must be one physical single-link file."
        )

    command = ["/bin/bash", str(prepare_script)]
    if release_notes is not None:
        command.append(str(release_notes))
    environment = dict(os.environ)
    environment["CADENCE_RELEASE_SUPERVISOR_PID"] = str(os.getpid())
    operation_token = secrets.token_hex(32)
    environment["CADENCE_RELEASE_OPERATION_TOKEN"] = operation_token

    child: subprocess.Popen[bytes] | None = None
    supervised_owner: dict[str, Any] | None = None
    pending_signals: list[int] = []
    forwarding_errors: list[OSError] = []
    received_signals: list[int] = []
    shutdown_deadline: list[float | None] = [None]

    def send_group_signal(signum: int) -> None:
        if child is None:
            pending_signals.append(signum)
            return
        try:
            os.killpg(child.pid, signum)
        except ProcessLookupError:
            pass
        except OSError as error:
            forwarding_errors.append(error)

    def forward_signal(signum: int, _frame: Any) -> None:
        received_signals.append(signum)
        if shutdown_deadline[0] is None:
            shutdown_deadline[0] = (
                time.monotonic() + RELEASE_SUPERVISOR_GRACE_SECONDS
            )
        send_group_signal(signum)

    forwarded_signals = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)
    previous_handlers = {
        signum: signal.getsignal(signum) for signum in forwarded_signals
    }
    try:
        for signum in forwarded_signals:
            signal.signal(signum, forward_signal)
        child = subprocess.Popen(
            command,
            env=environment,
            start_new_session=True,
        )
        try:
            child_group = os.getpgid(child.pid)
        except ProcessLookupError:
            child_group = child.pid
        if child_group != child.pid:
            send_group_signal(signal.SIGKILL)
            child.wait()
            raise ReleaseContractError(
                "Release preparation did not enter its dedicated process group."
            )
        supervised_owner = _process_identity(child.pid)
        if supervised_owner is None or supervised_owner["processGroup"] != child.pid:
            send_group_signal(signal.SIGKILL)
            child.wait()
            raise ReleaseContractError(
                "Release preparation owner identity could not be authenticated."
            )
        for signum in tuple(pending_signals):
            send_group_signal(signum)
        pending_signals.clear()

        forced_while_leader_alive = False
        while child.poll() is None:
            deadline = shutdown_deadline[0]
            if deadline is not None and time.monotonic() >= deadline:
                forced_while_leader_alive = True
                send_group_signal(signal.SIGKILL)
                break
            time.sleep(RELEASE_SUPERVISOR_POLL_SECONDS)
        return_code = child.wait()

        if _supervised_process_group_exists(child.pid):
            if shutdown_deadline[0] is None:
                shutdown_deadline[0] = (
                    time.monotonic() + RELEASE_SUPERVISOR_GRACE_SECONDS
                )
            while (
                _supervised_process_group_exists(child.pid)
                and time.monotonic() < shutdown_deadline[0]
            ):
                time.sleep(RELEASE_SUPERVISOR_POLL_SECONDS)
            if _supervised_process_group_exists(child.pid):
                send_group_signal(signal.SIGKILL)
                if forwarding_errors:
                    raise ReleaseContractError(
                        "The complete release process group could not be terminated."
                    )
            while _supervised_process_group_exists(child.pid):
                time.sleep(RELEASE_SUPERVISOR_POLL_SECONDS)
    finally:
        for signum, previous_handler in previous_handlers.items():
            signal.signal(signum, previous_handler)
    if forwarding_errors:
        raise ReleaseContractError(
            "A termination signal could not be forwarded to the complete "
            "release process group."
        )
    if forced_while_leader_alive and received_signals:
        return 128 + received_signals[0]
    if return_code < 0:
        return_code = 128 + abs(return_code)
    if return_code == 0 and received_signals:
        return 128 + received_signals[0]
    if return_code == 0:
        release_mode = environment.get("CADENCE_RELEASE_MODE", "")
        if release_mode not in {"local", "public"} or supervised_owner is None:
            raise ReleaseContractError(
                "Successful release preparation has no authenticated supervisor owner."
            )
        release_operation_end(
            trusted_root,
            release_mode,
            operation_token,
            supervised_owner,
        )
    return return_code


def main() -> int:
    parser = argparse.ArgumentParser(description="Cadence release surface validator")
    parser.add_argument(
        "command",
        choices=(
            "check",
            "env",
            "public-preflight",
            "gate-begin",
            "gate-complete",
            "release-preflight",
            "release-operation-begin",
            "release-operation-check",
            "release-operation-end",
            "release-checksums-write",
            "archive-stamp",
            "archive-check",
            "supervise-prepare",
        ),
        nargs="?",
        default="check",
    )
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--source-sha")
    parser.add_argument("--expect-sha")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--gate-session")
    parser.add_argument("--gate-owner-pid", type=int)
    parser.add_argument("--gate-receipt", action="append", default=[])
    parser.add_argument("--release-mode", choices=("local", "public"))
    parser.add_argument("--operation-token")
    parser.add_argument("--operation-owner-pid", type=int)
    parser.add_argument("--release-notes", type=Path)
    arguments = parser.parse_args()

    try:
        if arguments.command == "supervise-prepare":
            return supervise_prepare(arguments.root, arguments.release_notes)

        if arguments.command == "gate-begin":
            preflight = gate_begin(arguments.root, arguments.gate_owner_pid)
            print(f"SOURCE_SHA={shlex.quote(preflight.source.sha)}")
            print(
                "RELEASE_ATTESTATION_PATH="
                f"{shlex.quote(str(preflight.attestation_path))}"
            )
            print(f"RELEASE_GATE_SESSION={shlex.quote(preflight.gate_session)}")
            return 0

        if arguments.command == "gate-complete":
            if arguments.source_sha is None or arguments.gate_session is None:
                parser.error(
                    "gate-complete requires --source-sha and --gate-session"
                )
            path = gate_complete(
                arguments.root,
                arguments.source_sha,
                arguments.gate_session,
                arguments.gate_receipt,
                arguments.gate_owner_pid,
            )
            print(path)
            return 0

        if arguments.command == "release-operation-begin":
            if (
                arguments.release_mode is None
                or arguments.operation_owner_pid is None
            ):
                parser.error(
                    "release-operation-begin requires --release-mode and "
                    "--operation-owner-pid"
                )
            token, paths = release_operation_begin(
                arguments.root,
                arguments.release_mode,
                arguments.expect_sha,
                arguments.operation_owner_pid,
                arguments.operation_token,
            )
            print(f"RELEASE_OPERATION_TOKEN={shlex.quote(token)}")
            for key, value in paths.items():
                print(f"{key}={shlex.quote(str(value))}")
            return 0

        if arguments.command in {
            "release-operation-check",
            "release-operation-end",
            "release-checksums-write",
        }:
            if arguments.release_mode is None or arguments.operation_token is None:
                parser.error(
                    f"{arguments.command} requires --release-mode and "
                    "--operation-token"
                )
            if (
                arguments.command != "release-operation-end"
                and arguments.operation_owner_pid is None
            ):
                parser.error(
                    f"{arguments.command} requires --operation-owner-pid"
                )
            if arguments.command == "release-operation-check":
                release_operation_check(
                    arguments.root,
                    arguments.release_mode,
                    arguments.operation_token,
                    arguments.operation_owner_pid,
                )
                print("Release operation path identities passed.")
            elif arguments.command == "release-operation-end":
                release_operation_end(
                    arguments.root,
                    arguments.release_mode,
                    arguments.operation_token,
                )
                print("Release operation ended.")
            else:
                print(
                    release_checksums_write(
                        arguments.root,
                        arguments.release_mode,
                        arguments.operation_token,
                        arguments.operation_owner_pid,
                    )
                )
            return 0

        if arguments.command == "release-preflight":
            preflight = release_preflight(arguments.root, arguments.expect_sha)
            print(f"SOURCE_SHA={shlex.quote(preflight.source.sha)}")
            print(
                "RELEASE_ATTESTATION_PATH="
                f"{shlex.quote(str(preflight.attestation_path))}"
            )
            print(
                "RELEASE_ATTESTATION_SHA256="
                f"{shlex.quote(preflight.attestation_sha256)}"
            )
            if arguments.release_notes is not None:
                notes_path = validate_release_notes_path(
                    arguments.root,
                    arguments.release_notes,
                    preflight.source,
                )
                print(f"RELEASE_NOTES_PATH={shlex.quote(str(notes_path))}")
            if arguments.release_mode is not None:
                for key, value in release_output_paths(
                    arguments.root, arguments.release_mode
                ).items():
                    print(f"{key}={shlex.quote(str(value))}")
            return 0

        if arguments.command in {"archive-stamp", "archive-check"}:
            if arguments.archive is None or arguments.source_sha is None:
                parser.error(
                    f"{arguments.command} requires --archive and --source-sha"
                )
            if arguments.command == "archive-stamp":
                print(
                    archive_stamp(
                        arguments.root, arguments.archive, arguments.source_sha
                    )
                )
            else:
                archive_check(
                    arguments.root, arguments.archive, arguments.source_sha
                )
                print("Archive provenance passed.")
            return 0
    except ReleaseContractError as error:
        print(f"Release provenance failed: {error}", file=sys.stderr)
        return 1

    try:
        if arguments.command == "env":
            for key, value in environment_values(arguments.root).items():
                if "\n" in value or "\r" in value:
                    raise ReleaseContractError(f"{key} contains a newline.")
                print(f"{key}={shlex.quote(value)}")
            return 0

        errors = validate_product_surfaces(arguments.root)
        if arguments.command == "public-preflight":
            errors.extend(validate_public_release_environment(arguments.root))
        if errors:
            for error in errors:
                print(f"- {error}")
            return 1
        values = environment_values(arguments.root)
        print(
            "Cadence release contract passed for "
            f'{values["PUBLIC_VERSION"]} ({values["BUILD_NUMBER"]})'
        )
        return 0
    except (KeyError, TypeError, ValueError) as error:
        print(
            f"Release contract failed: malformed release manifest ({error}).",
            file=sys.stderr,
        )
        return 1
    except ReleaseContractError as error:
        print(f"Release contract failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
