#!/usr/bin/env python3
"""Audit a repository against the embedded QenTerra governance standard."""

from __future__ import annotations

import argparse
import codecs
import fnmatch
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import unquote


TOOL_VERSION = "1.3.0"
STANDARD_VERSION = "1.3.0"
CONFIG_PATH = Path(".github/qenterra-repository.json")
COPYRIGHT_HOLDER = "Nikita Melnychenko (QenTerra)"
GITHUB_OWNER = "QenTerra"
CONTACT_EMAIL = "contact@qenterra.com"
SUPPORT_EMAIL = "support@qenterra.com"
OBSOLETE_FUNDING_MARKERS = (
    " ".join(("buy", "me", "a", "coffee")),
    "".join(("buy", "me", "a", "coffee", ".com")),
)

REQUIRED_CONFIG_KEYS = frozenset(
    {
        "$schema",
        "standard_version",
        "profile",
        "overlays",
        "visibility",
        "license",
        "version_scheme",
        "collaboration_model",
        "ecosystem",
        "dependabot_ecosystem",
        "project_name",
        "repository_name",
        "description",
        "github_owner",
        "repository_url",
        "homepage_url",
        "copyright_holder",
        "copyright_year_range",
        "current_version",
        "version_source",
        "version_tag_prefix",
        "release_mode",
        "default_branch",
        "branch_prefix",
        "merge_strategy",
        "topics",
        "github_features",
        "documentation_root",
        "wiki_source",
        "primary_language",
        "minimum_requirements",
        "install_command",
        "quick_start_command",
        "verification_command",
        "support_url",
        "security_url",
        "conduct_contact",
        "code_owner",
        "allowed_root_paths",
        "published_artifacts",
        "exceptions",
        "governance",
    }
)

STRING_CONFIG_KEYS = frozenset(
    {
        "$schema",
        "standard_version",
        "profile",
        "visibility",
        "license",
        "version_scheme",
        "collaboration_model",
        "ecosystem",
        "dependabot_ecosystem",
        "project_name",
        "repository_name",
        "description",
        "github_owner",
        "repository_url",
        "homepage_url",
        "copyright_holder",
        "copyright_year_range",
        "current_version",
        "version_source",
        "version_tag_prefix",
        "release_mode",
        "default_branch",
        "branch_prefix",
        "merge_strategy",
        "documentation_root",
        "wiki_source",
        "primary_language",
        "minimum_requirements",
        "install_command",
        "quick_start_command",
        "verification_command",
        "support_url",
        "security_url",
        "conduct_contact",
        "code_owner",
    }
)

CORE_FILES = frozenset(
    {
        ".editorconfig",
        ".gitattributes",
        ".github/CODEOWNERS",
        ".github/dependabot.yml",
        ".github/PULL_REQUEST_TEMPLATE.md",
        ".github/qenterra-repository.json",
        ".github/qenterra-repository.schema.json",
        ".github/release.yml",
        ".github/workflows/repository-governance.yml",
        ".gitignore",
        "AUTHORS.md",
        "CHANGELOG.md",
        "GOVERNANCE.md",
        "MAINTAINERS.md",
        "SECURITY.md",
        "THIRD_PARTY_NOTICES.md",
        "docs/ARCHITECTURE.md",
        "docs/DEPENDENCIES.md",
        "docs/DEVELOPMENT.md",
        "docs/GITHUB_SETTINGS.md",
        "docs/MAINTENANCE.md",
        "docs/README.md",
        "docs/RELEASING.md",
        "docs/STYLE_GUIDE.md",
        "docs/TESTING.md",
        "docs/TROUBLESHOOTING.md",
        "docs/decisions/0000-template.md",
        "docs/decisions/README.md",
        "scripts/qenterra_repository_check.py",
    }
)

COLLABORATION_FILES = frozenset(
    {
        ".github/ISSUE_TEMPLATE/01-bug.yml",
        ".github/ISSUE_TEMPLATE/02-feature.yml",
        ".github/ISSUE_TEMPLATE/03-documentation.yml",
        ".github/ISSUE_TEMPLATE/config.yml",
        ".github/PULL_REQUEST_TEMPLATE.md",
        ".github/labels.yml",
        "CODE_OF_CONDUCT.md",
        "CONTRIBUTING.md",
        "SUPPORT.md",
    }
)

PROFILE_FILES = {
    "application": frozenset({"README.md", "docs/UPDATES.md"}),
    "library": frozenset(
        {"README.md", "docs/API.md", "docs/COMPATIBILITY.md", "docs/MIGRATION.md"}
    ),
    "cli": frozenset({"README.md", "docs/COMMAND_REFERENCE.md", "docs/CONFIGURATION.md"}),
    "service": frozenset(
        {"README.md", "docs/API.md", "docs/CONFIGURATION.md", "docs/DEPLOYMENT.md"}
    ),
    "documentation": frozenset(
        {"README.md", "docs/EDITORIAL_STYLE.md", "docs/SOURCE_POLICY.md"}
    ),
    "monorepo": frozenset(
        {"README.md", "docs/OWNERSHIP.md", "docs/REPOSITORY_STRUCTURE.md"}
    ),
    "private": frozenset(
        {"README.md", "docs/DATA_CLASSIFICATION.md", "docs/RETENTION.md"}
    ),
}

PROFILE_REQUIRED_OVERLAYS = {
    "application": frozenset(),
    "library": frozenset(),
    "cli": frozenset(),
    "service": frozenset({"service-operations"}),
    "documentation": frozenset(),
    "monorepo": frozenset(),
    "private": frozenset(),
}

PROFILE_COMPATIBLE_OVERLAYS = {
    "application": frozenset(
        {"product-legal", "service-operations", "citation", "community-discussions", "github-wiki"}
    ),
    "library": frozenset({"package", "citation", "community-discussions", "github-wiki"}),
    "cli": frozenset({"package", "citation", "community-discussions", "github-wiki"}),
    "service": frozenset(
        {"product-legal", "service-operations", "citation", "community-discussions", "github-wiki"}
    ),
    "documentation": frozenset({"citation", "community-discussions", "github-wiki"}),
    "monorepo": frozenset(
        {"package", "service-operations", "citation", "community-discussions", "github-wiki"}
    ),
    "private": frozenset({"service-operations"}),
}

OVERLAY_FILES = {
    "product-legal": frozenset({"PRIVACY.md", "TERMS_OF_USE.md"}),
    "package": frozenset({"docs/DEPRECATION.md", "docs/PACKAGE_RELEASE.md"}),
    "service-operations": frozenset(
        {"docs/INCIDENT_RESPONSE.md", "docs/OPERATIONS.md", "docs/SERVICE_LEVELS.md"}
    ),
    "citation": frozenset({"CITATION.cff"}),
    "community-discussions": frozenset(
        {".github/DISCUSSION_TEMPLATE/ideas.yml", ".github/DISCUSSION_TEMPLATE/questions.yml"}
    ),
    "github-wiki": frozenset(
        {
            "docs/wiki/Architecture.md",
            "docs/wiki/Development.md",
            "docs/wiki/Getting-Started.md",
            "docs/wiki/Home.md",
            "docs/wiki/Release-Process.md",
            "docs/wiki/Troubleshooting.md",
            "docs/wiki/_Footer.md",
            "docs/wiki/_Sidebar.md",
        }
    ),
}

LICENSE_FILES = {
    "MIT": frozenset({"LICENSE"}),
    "Apache-2.0": frozenset({"LICENSE", "NOTICE"}),
    "MPL-2.0": frozenset({"LICENSE", "NOTICE"}),
    "GPL-3.0-only": frozenset({"LICENSE", "NOTICE"}),
    "AGPL-3.0-only": frozenset({"LICENSE", "NOTICE"}),
    "Proprietary": frozenset({"LICENSE"}),
}

LICENSE_MARKERS = {
    "MIT": "Permission is hereby granted, free of charge",
    "Apache-2.0": "Apache License\nVersion 2.0, January 2004",
    "MPL-2.0": "Mozilla Public License Version 2.0",
    "GPL-3.0-only": "GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007",
    "AGPL-3.0-only": "GNU AFFERO GENERAL PUBLIC LICENSE\nVersion 3, 19 November 2007",
    "Proprietary": "All rights reserved.",
}

README_HEADINGS = {
    "application": ("## Status", "## Requirements", "## Install", "## Privacy and security", "## Contact", "## License"),
    "library": ("## Status", "## Requirements", "## Install", "## API and compatibility", "## Contact", "## License"),
    "cli": ("## Status and requirements", "## Install", "## Commands and configuration", "## Contact", "## License"),
    "service": ("## Status", "## Service boundary", "## Data, privacy, and security", "## Operations", "## Contact", "## License"),
    "documentation": ("## Audience and scope", "## Read", "## Quality", "## Sources and changes", "## Contact"),
    "monorepo": ("## Workspace", "## Ownership and boundaries", "## Version and release model", "## Contact", "## License"),
    "private": ("## Status and access", "## Scope", "## Data and recovery", "## Contact", "## License"),
}

DEFAULT_ROOT_PATHS = frozenset(
    {
        ".git",
        ".github",
        ".swiftpm",
        "Sources",
        "Tests",
        "apps",
        "assets",
        "docs",
        "examples",
        "packages",
        "release",
        "scripts",
        "src",
        "tests",
        "tools",
        "Cargo.lock",
        "Cargo.toml",
        "CMakeLists.txt",
        "Dockerfile",
        "Gemfile",
        "Gemfile.lock",
        "Makefile",
        "Package.resolved",
        "Package.swift",
        "go.mod",
        "go.sum",
        "package-lock.json",
        "package.json",
        "pnpm-lock.yaml",
        "pyproject.toml",
        "requirements.txt",
        "uv.lock",
        "yarn.lock",
    }
)
PUBLIC_AGENT_DIRECTORY_NAMES = frozenset(('.agent', '.agents', '.aider', '.augment', '.claude', '.cline', '.codex', '.continue', '.copilot', '.cursor', '.factory', '.gemini', '.junie', '.openhands', '.qoder', '.roo', '.skills', '.superpowers', '.windsurf', '_agents'))
PUBLIC_AGENT_FILE_NAMES = frozenset(('.aider.conf.yml', '.aiderignore', '.claudeignore', '.clinerules', '.continueignore', '.copilotignore', '.cursorignore', '.cursorrules', '.geminiignore', '.mcp.json', '.qoderignore', '.windsurfrules', 'copilot-instructions.md', 'mcp.json'))
PUBLIC_AGENT_FILE_PATTERNS = ('agents.md', 'agents.*.md', 'claude.md', 'claude.*.md', 'copilot.md', 'copilot.*.md', 'gemini.md', 'gemini.*.md', 'skill.md', 'skill.*.md', '*.agent.md', '*.chatmode.md', '*.instructions.md', '*.prompt.md')
PUBLIC_AGENT_PATH_PREFIXES = ('.github/agents', '.github/chatmodes', '.github/hooks', '.github/instructions', '.github/prompts', '.github/skills')
PUBLIC_CACHE_DIRECTORY_NAMES = frozenset(('.build', '.cache', '.dart_tool', '.gradle', '.hypothesis', '.mypy_cache', '.next', '.nox', '.npm', '.nuxt', '.nyc_output', '.output', '.parcel-cache', '.pnpm-store', '.pytest_cache', '.ruff_cache', '.sass-cache', '.svelte-kit', '.tox', '.turbo', '.venv', '.vite', '.wxt', '__pycache__', 'coverage', 'deriveddata', 'htmlcov', 'node_modules', 'playwright-report', 'target', 'test-results', 'tmp', 'venv'))
PUBLIC_CACHE_FILE_NAMES = frozenset(('.coverage', '.ds_store', '.eslintcache', '.stylelintcache', 'coverage.xml', 'junit.xml', 'thumbs.db'))
PUBLIC_CACHE_FILE_PATTERNS = ('.coverage.*', '*.log', '*.profdata', '*.profraw', '*.pyc', '*.pyo', '*.swo', '*.swp', '*.tmp', '*~')
PUBLIC_CACHE_PATH_PREFIXES = ('.yarn/cache', 'artifacts/qa')
PUBLIC_GENERATED_DIRECTORY_NAMES = frozenset(('build', 'dist', 'generated'))
PUBLIC_GENERATED_HEADER_MARKERS = ('@generated', '<auto-generated', 'code generated by', 'generated by')
GENERATED_HEADER_LINE_COUNT = 8
GENERATED_HEADER_LINE_MAX_BYTES = 16_384
PUBLISHED_ARTIFACT_MANIFEST_SCHEMA_VERSION = 1
DEPENDABOT_ECOSYSTEMS = frozenset(
    {
        "bazel", "bun", "bundler", "cargo", "composer", "conda", "deno", "devcontainers",
        "docker", "docker-compose", "dotnet-sdk", "elm", "gitsubmodule", "gomod", "gradle",
        "helm", "julia", "maven", "mix", "nix", "none", "npm", "nuget", "opentofu", "pip",
        "pre-commit", "pub", "rust-toolchain", "sbt", "swift", "terraform", "uv", "vcpkg",
    }
)

WINDOWS_RESERVED_NAMES = frozenset(
    {"CON", "PRN", "AUX", "NUL", *(f"COM{number}" for number in range(1, 10)), *(f"LPT{number}" for number in range(1, 10))}
)

COMMIT_RE = re.compile(
    r"^(?P<type>feat|fix|docs|refactor|perf|test|build|ci|chore|security|release|revert)"
    r"(?:\((?P<scope>[a-z0-9]+(?:-[a-z0-9]+)*)\))?"
    r"(?P<breaking>!)?: (?P<description>[^\n]+)$"
)
SEMVER_RE = re.compile(
    r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
    r"(?:-(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\Z"
)
CALVER_RE = re.compile(r"20\d{2}\.(?:0[1-9]|1[0-2])\.(?:0[1-9]|[12]\d|3[01])(?:\.(?:0|[1-9]\d*))?\Z")
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
PLACEHOLDER_RE = re.compile(r"\{\{[A-Z][A-Z0-9_]*\}\}")
DRAFT_MARKER = "QENTERRA_DRAFT_REVIEW_REQUIRED"
ACTION_USE_RE = re.compile(r"^\s*uses:\s*([^\s#]+)", re.MULTILINE)
PINNED_SHA_RE = re.compile(r"[0-9a-fA-F]{40}\Z")
REPOSITORY_NAME_RE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
SEVERITY_ORDER = {"error": 0, "warning": 1, "unverified": 2}


@dataclass(frozen=True)
class Finding:
    code: str
    severity: str
    message: str
    path: str | None = None
    remediation: str | None = None

    def to_dict(self) -> dict[str, Any]:
        value: dict[str, Any] = {
            "code": self.code,
            "severity": self.severity,
            "message": self.message,
        }
        if self.path is not None:
            value["path"] = self.path
        if self.remediation is not None:
            value["remediation"] = self.remediation
        return value


def finding(
    code: str,
    severity: str,
    message: str,
    *,
    path: str | None = None,
    remediation: str | None = None,
) -> Finding:
    return Finding(code, severity, message, path, remediation)


def sorted_findings(values: Iterable[Finding]) -> list[Finding]:
    return sorted(
        values,
        key=lambda item: (SEVERITY_ORDER[item.severity], item.code, item.path or "", item.message),
    )


def validate_commit_message(message: str) -> list[Finding]:
    normalized = message.replace("\r\n", "\n").strip("\n")
    if not normalized:
        return [finding("COMMIT_MESSAGE_EMPTY", "error", "Commit message is empty.")]
    subject, *body = normalized.split("\n")
    findings: list[Finding] = []
    if subject.startswith(("fixup!", "squash!")):
        findings.append(
            finding("COMMIT_FIXUP_FORBIDDEN", "error", "Published history must not contain fixup or squash commits.")
        )
    match = COMMIT_RE.fullmatch(subject)
    if match is None:
        findings.append(
            finding(
                "COMMIT_SUBJECT_INVALID",
                "error",
                "Subject must follow the QenTerra Conventional Commit grammar.",
                remediation="Use '<type>(optional-kebab-scope)[!]: <imperative description>'.",
            )
        )
        return findings
    if len(subject) > 72:
        findings.append(finding("COMMIT_SUBJECT_TOO_LONG", "error", "Commit subject exceeds 72 characters."))
    description = match.group("description")
    if description.endswith("."):
        findings.append(finding("COMMIT_SUBJECT_PERIOD", "error", "Commit subject must not end with a period."))
    if description.casefold().startswith(("wip", "work in progress", "update stuff", "changes")):
        findings.append(finding("COMMIT_DESCRIPTION_VAGUE", "error", "Commit description names activity instead of an observable change."))
    has_breaking_footer = any(line.startswith("BREAKING CHANGE: ") for line in body)
    if match.group("breaking") and not has_breaking_footer:
        findings.append(
            finding("COMMIT_BREAKING_MIGRATION_MISSING", "error", "Breaking commit lacks a migration footer.")
        )
    if has_breaking_footer and not match.group("breaking"):
        findings.append(
            finding("COMMIT_BREAKING_MARKER_MISSING", "error", "Breaking footer is present but the subject lacks '!'.")
        )
    for index, line in enumerate(body, start=2):
        if len(line) > 100 and re.search(r"https?://|\S{80,}", line) is None:
            findings.append(finding("COMMIT_BODY_LINE_TOO_LONG", "warning", f"Commit body line {index} exceeds 100 characters."))
    return findings


def validate_version(value: str, scheme: str) -> list[Finding]:
    if scheme == "semver":
        valid = SEMVER_RE.fullmatch(value)
        version_without_build = value.split("+", 1)[0]
        if valid is not None and "-" in version_without_build:
            prerelease = version_without_build.split("-", 1)[1]
            valid = re.fullmatch(r"(?:alpha|beta|rc)\.(?:0|[1-9]\d*)", prerelease)
    elif scheme == "calver":
        valid = CALVER_RE.fullmatch(value)
        if valid is not None:
            try:
                datetime.strptime(".".join(value.split(".")[:3]), "%Y.%m.%d")
            except ValueError:
                valid = None
    else:
        valid = None
    if valid is not None:
        return []
    return [finding("VERSION_INVALID", "error", f"Version {value!r} does not match {scheme!r}.")]


def validate_branch_name(value: str) -> list[Finding]:
    valid = (
        value == "main"
        or re.fullmatch(r"qenterra/[a-z0-9]+(?:-[a-z0-9]+)*", value) is not None
        or re.fullmatch(r"(?:dependabot|renovate)/[A-Za-z0-9._/-]+", value) is not None
    )
    if valid and ".." not in value and "//" not in value and not value.endswith(("/", ".")):
        return []
    return [finding("BRANCH_NAME_INVALID", "error", f"Branch {value!r} does not match the QenTerra branch contract.")]


def read_text(path: Path) -> str | None:
    try:
        if path.is_symlink():
            return None
        if path.stat().st_size > 2_000_000:
            return None
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return None


def load_config(root: Path, findings: list[Finding]) -> dict[str, Any] | None:
    path = root / CONFIG_PATH
    if not path.is_file():
        findings.append(
            finding("CONFIG_MISSING", "error", "Repository contract is missing.", path=CONFIG_PATH.as_posix())
        )
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        findings.append(
            finding("CONFIG_INVALID_JSON", "error", f"Repository contract is not valid UTF-8 JSON: {exc}", path=CONFIG_PATH.as_posix())
        )
        return None
    if not isinstance(value, dict):
        findings.append(finding("CONFIG_INVALID", "error", "Repository contract must be a JSON object.", path=CONFIG_PATH.as_posix()))
        return None
    return value


def validate_contract(config: dict[str, Any], findings: list[Finding]) -> bool:
    missing = sorted(REQUIRED_CONFIG_KEYS - config.keys())
    unexpected = sorted(set(config) - REQUIRED_CONFIG_KEYS - {"governance"})
    if missing:
        findings.append(
            finding("CONFIG_KEYS_MISSING", "error", f"Repository contract is missing keys: {', '.join(missing)}.", path=CONFIG_PATH.as_posix())
        )
    if unexpected:
        findings.append(
            finding("CONFIG_KEYS_UNKNOWN", "error", f"Repository contract contains unknown keys: {', '.join(unexpected)}.", path=CONFIG_PATH.as_posix())
        )
    invalid_string_keys = sorted(
        key
        for key in STRING_CONFIG_KEYS
        if key in config and (not isinstance(config[key], str) or not config[key].strip())
    )
    if invalid_string_keys:
        findings.append(
            finding(
                "CONFIG_VALUE_TYPE_INVALID",
                "error",
                f"Repository contract keys must be non-empty strings: {', '.join(invalid_string_keys)}.",
                path=CONFIG_PATH.as_posix(),
            )
        )
    if config.get("standard_version") != STANDARD_VERSION:
        findings.append(
            finding("STANDARD_VERSION_MISMATCH", "error", f"Contract must select standard {STANDARD_VERSION}.", path=CONFIG_PATH.as_posix())
        )
    if config.get("$schema") != "./qenterra-repository.schema.json":
        findings.append(finding("SCHEMA_REFERENCE_INVALID", "error", "Contract must reference the local versioned JSON Schema."))
    if config.get("copyright_holder") != COPYRIGHT_HOLDER:
        findings.append(
            finding("IDENTITY_MISMATCH", "error", f"copyright_holder must be exactly {COPYRIGHT_HOLDER!r}.", path=CONFIG_PATH.as_posix())
        )
    if config.get("github_owner") != GITHUB_OWNER:
        findings.append(
            finding("OWNER_MISMATCH", "error", f"github_owner must be exactly {GITHUB_OWNER!r}.", path=CONFIG_PATH.as_posix())
        )

    profile = config.get("profile")
    overlays = config.get("overlays")
    license_id = config.get("license")
    visibility = config.get("visibility")
    if not isinstance(profile, str) or profile not in PROFILE_FILES:
        findings.append(finding("PROFILE_INVALID", "error", f"Unknown repository profile: {profile!r}."))
    if not isinstance(overlays, list) or any(not isinstance(item, str) for item in overlays):
        findings.append(finding("OVERLAYS_INVALID", "error", "overlays must be an array of strings."))
    elif isinstance(profile, str) and profile in PROFILE_FILES:
        if len(overlays) != len(set(overlays)):
            findings.append(finding("OVERLAY_DUPLICATE", "error", "overlays must not contain duplicates."))
        unknown = sorted(set(overlays) - OVERLAY_FILES.keys())
        incompatible = sorted(set(overlays) - PROFILE_COMPATIBLE_OVERLAYS[profile])
        required = sorted(PROFILE_REQUIRED_OVERLAYS[profile] - set(overlays))
        if unknown:
            findings.append(finding("OVERLAY_UNKNOWN", "error", f"Unknown overlays: {', '.join(unknown)}."))
        if incompatible:
            findings.append(finding("OVERLAY_INCOMPATIBLE", "error", f"Profile {profile!r} cannot use: {', '.join(incompatible)}."))
        if required:
            findings.append(finding("OVERLAY_REQUIRED", "error", f"Profile {profile!r} requires: {', '.join(required)}."))
    if not isinstance(license_id, str) or license_id not in LICENSE_FILES:
        findings.append(finding("LICENSE_INVALID", "error", f"Unknown license mode: {license_id!r}."))
    if not isinstance(visibility, str) or visibility not in {"public", "private"}:
        findings.append(finding("VISIBILITY_INVALID", "error", "visibility must be 'public' or 'private'."))
    if profile == "private" and visibility != "private":
        findings.append(finding("PRIVATE_PROFILE_VISIBLE", "error", "The private profile requires private visibility."))
    if not isinstance(config.get("collaboration_model"), str) or config.get("collaboration_model") not in {"solo", "team"}:
        findings.append(finding("COLLABORATION_MODEL_INVALID", "error", "collaboration_model must be 'solo' or 'team'."))
    if not isinstance(config.get("dependabot_ecosystem"), str) or config.get("dependabot_ecosystem") not in DEPENDABOT_ECOSYSTEMS:
        findings.append(finding("DEPENDABOT_ECOSYSTEM_INVALID", "error", "dependabot_ecosystem is unsupported; use a current GitHub YAML value or 'none'."))
    exact_controls = {
        "version_tag_prefix": "v",
        "default_branch": "main",
        "branch_prefix": "qenterra/",
        "merge_strategy": "squash",
        "documentation_root": "docs",
    }
    for key, expected in exact_controls.items():
        if config.get(key) != expected:
            findings.append(finding("REPOSITORY_CONTROL_INVALID", "error", f"{key} must be exactly {expected!r}."))
    if not isinstance(config.get("release_mode"), str) or config.get("release_mode") not in {"github-releases", "package-registry", "deployment", "none"}:
        findings.append(finding("RELEASE_MODE_INVALID", "error", "release_mode is not recognised."))

    repository_name = config.get("repository_name")
    if not isinstance(repository_name, str) or REPOSITORY_NAME_RE.fullmatch(repository_name) is None or len(repository_name) > 100:
        findings.append(finding("REPOSITORY_NAME_INVALID", "error", "repository_name must use lowercase ASCII kebab-case and be at most 100 characters."))
    elif config.get("repository_url") != f"https://github.com/{GITHUB_OWNER}/{repository_name}":
        findings.append(finding("REPOSITORY_URL_INVALID", "error", "repository_url does not match the canonical owner and slug."))
    description = config.get("description")
    if not isinstance(description, str) or not description.strip() or len(description) > 350 or "\n" in description:
        findings.append(finding("DESCRIPTION_INVALID", "error", "description must be one non-empty line of at most 350 characters."))
    for key in ("homepage_url", "support_url", "security_url"):
        if not isinstance(config.get(key), str) or not config[key].startswith("https://"):
            findings.append(finding("URL_INVALID", "error", f"{key} must use https://."))
    contact = config.get("conduct_contact")
    if not isinstance(contact, str) or not contact.startswith(("https://", "mailto:")):
        findings.append(finding("CONDUCT_CONTACT_INVALID", "error", "conduct_contact must use https:// or mailto:."))
    code_owner = config.get("code_owner")
    if not isinstance(code_owner, str) or re.fullmatch(r"@[A-Za-z0-9-]+(?:/[A-Za-z0-9_.-]+)?", code_owner) is None:
        findings.append(finding("CODE_OWNER_INVALID", "error", "code_owner must be a GitHub user or organisation/team handle."))
    year_range = config.get("copyright_year_range")
    year_match = re.fullmatch(r"(\d{4})(?:-(\d{4}))?", year_range) if isinstance(year_range, str) else None
    if year_match is None or not 1900 <= int(year_match.group(1)) <= 2099 or (year_match.group(2) and not int(year_match.group(1)) <= int(year_match.group(2)) <= 2099):
        findings.append(finding("COPYRIGHT_YEAR_INVALID", "error", "copyright_year_range must be chronological YYYY or YYYY-YYYY."))

    if not isinstance(config.get("version_scheme"), str) or config.get("version_scheme") not in {"semver", "calver"}:
        findings.append(finding("VERSION_SCHEME_INVALID", "error", "version_scheme must be 'semver' or 'calver'."))
    elif isinstance(config.get("current_version"), str):
        findings.extend(validate_version(config["current_version"], config["version_scheme"]))
    if config.get("version_scheme") == "calver" and profile not in {"documentation", "service"}:
        findings.append(finding("CALVER_PROFILE_INVALID", "error", "CalVer is allowed only for documentation or service profiles."))

    topics = config.get("topics")
    if (
        not isinstance(topics, list)
        or any(not isinstance(item, str) for item in topics)
        or not 5 <= len(topics) <= 12
        or len(topics) != len(set(topics))
        or any(REPOSITORY_NAME_RE.fullmatch(item) is None or len(item) > 50 for item in topics)
    ):
        findings.append(finding("TOPICS_INVALID", "error", "topics must contain 5 to 12 unique lowercase kebab-case values."))
    features = config.get("github_features")
    feature_keys = {"issues", "discussions", "wiki", "projects"}
    if (
        not isinstance(features, dict)
        or set(features) != feature_keys
        or any(not isinstance(features[key], bool) for key in feature_keys)
    ):
        findings.append(finding("GITHUB_FEATURES_INVALID", "error", "github_features must declare four boolean feature switches."))
    elif isinstance(overlays, list):
        if profile != "private" and not features["issues"]:
            findings.append(finding("GITHUB_ISSUES_REQUIRED", "error", "Non-private profiles require Issues for generated forms."))
        if features["discussions"] != ("community-discussions" in overlays):
            findings.append(finding("GITHUB_DISCUSSIONS_DRIFT", "error", "Discussions setting and overlay disagree."))
        if features["wiki"] != ("github-wiki" in overlays):
            findings.append(finding("GITHUB_WIKI_DRIFT", "error", "Wiki setting and overlay disagree."))
        expected_wiki_source = "docs/wiki" if features["wiki"] else "disabled"
        if config.get("wiki_source") != expected_wiki_source:
            findings.append(finding("WIKI_SOURCE_INVALID", "error", f"wiki_source must be {expected_wiki_source!r}."))

    allowed = config.get("allowed_root_paths")
    if not isinstance(allowed, list) or any(not isinstance(item, str) or "/" in item or not item for item in allowed):
        findings.append(finding("ALLOWED_ROOT_PATHS_INVALID", "error", "allowed_root_paths must contain top-level relative names."))

    published_artifacts = config.get("published_artifacts")
    required_artifact_keys = {
        "path", "purpose", "source", "manifest", "verification_command", "review_trigger"
    }
    if not isinstance(published_artifacts, list):
        findings.append(finding("PUBLISHED_ARTIFACTS_INVALID", "error", "published_artifacts must be an array."))
    else:
        artifact_paths: set[str] = set()
        for index, artifact in enumerate(published_artifacts):
            if (
                not isinstance(artifact, dict)
                or set(artifact) != required_artifact_keys
                or any(
                    not isinstance(artifact.get(key), str) or not artifact[key].strip()
                    for key in required_artifact_keys
                )
            ):
                findings.append(finding("PUBLISHED_ARTIFACT_INVALID", "error", f"published_artifacts[{index}] is incomplete."))
                continue
            relative_fields = (artifact["path"], artifact["source"], artifact["manifest"])
            if any(
                value.startswith(("/", "\\"))
                or "\\" in value
                or any(part in {"", ".", ".."} for part in value.split("/"))
                for value in relative_fields
            ):
                findings.append(finding("PUBLISHED_ARTIFACT_PATH_INVALID", "error", f"published_artifacts[{index}] contains an unsafe relative path."))
                continue
            artifact_path, source_path, manifest_path = relative_fields
            if not manifest_path.casefold().endswith(".json"):
                findings.append(finding("PUBLISHED_ARTIFACT_MANIFEST_PATH_INVALID", "error", f"published_artifacts[{index}].manifest must be a JSON checksum manifest."))
            if len(artifact["purpose"].strip()) < 12:
                findings.append(finding("PUBLISHED_ARTIFACT_PURPOSE_INVALID", "error", f"published_artifacts[{index}].purpose must state a concrete consumer purpose."))
            if artifact_verification_entrypoint(artifact["verification_command"]) is None:
                findings.append(finding("PUBLISHED_ARTIFACT_VERIFICATION_INVALID", "error", f"published_artifacts[{index}].verification_command must invoke a versioned scripts/ verify, check, or audit entrypoint."))
            if len(artifact["review_trigger"].strip()) < 12 or artifact["review_trigger"].strip().casefold() in {"n/a", "na", "never", "none"}:
                findings.append(finding("PUBLISHED_ARTIFACT_REVIEW_TRIGGER_INVALID", "error", f"published_artifacts[{index}].review_trigger must name a real regeneration event."))
            values = (artifact_path, source_path, manifest_path)
            if len(set(values)) != len(values) or any(
                left.startswith(right + "/") or right.startswith(left + "/")
                for left in values
                for right in values
                if left != right
            ):
                findings.append(finding("PUBLISHED_ARTIFACT_PATH_OVERLAP", "error", f"published_artifacts[{index}] path, source, and manifest must be non-overlapping."))
            if artifact["path"] in artifact_paths:
                findings.append(finding("PUBLISHED_ARTIFACT_DUPLICATE", "error", f"published_artifacts repeats {artifact['path']!r}."))
            artifact_paths.add(artifact["path"])
        for left in artifact_paths:
            for right in artifact_paths:
                if left != right and (left.startswith(right + "/") or right.startswith(left + "/")):
                    findings.append(finding("PUBLISHED_ARTIFACT_PATH_OVERLAP", "error", f"published_artifacts paths overlap: {left!r} and {right!r}."))

    exceptions = config.get("exceptions")
    required_exception_keys = {"rule", "path_or_setting", "reason", "owner", "approval_source", "review_trigger"}
    if not isinstance(exceptions, list):
        findings.append(finding("EXCEPTIONS_INVALID", "error", "exceptions must be an array."))
    else:
        for index, exception in enumerate(exceptions):
            if (
                not isinstance(exception, dict)
                or set(exception) != required_exception_keys
                or any(
                    not isinstance(exception.get(key), str) or not exception[key].strip()
                    for key in required_exception_keys
                )
            ):
                findings.append(finding("EXCEPTION_INVALID", "error", f"exceptions[{index}] is incomplete."))
    if license_id == "Proprietary" and visibility == "public" and isinstance(exceptions, list):
        if not any(isinstance(item, dict) and item.get("rule") == "proprietary-public-distribution" for item in exceptions):
            findings.append(finding("PROPRIETARY_PUBLIC_UNAPPROVED", "error", "Public proprietary source requires an explicit distribution exception."))

    unresolved_values: list[str] = []
    for key, value in config.items():
        if not isinstance(value, str):
            continue
        folded = value.casefold()
        if "replace-with-" in folded or "path/to/" in folded or folded.startswith("state the "):
            unresolved_values.append(key)
    if unresolved_values:
        findings.append(
            finding(
                "CONFIG_VALUE_UNRESOLVED",
                "error",
                f"Repository contract still contains example values: {', '.join(sorted(unresolved_values))}.",
                path=CONFIG_PATH.as_posix(),
            )
        )
    return (
        not missing
        and not unexpected
        and not invalid_string_keys
        and isinstance(profile, str)
        and profile in PROFILE_FILES
        and isinstance(overlays, list)
        and all(isinstance(item, str) and item in OVERLAY_FILES for item in overlays)
        and isinstance(license_id, str)
        and license_id in LICENSE_FILES
    )


def expected_files(config: dict[str, Any]) -> set[str]:
    profile = str(config["profile"])
    result = set(CORE_FILES) | set(PROFILE_FILES[profile]) | set(LICENSE_FILES[str(config["license"])])
    if config["visibility"] == "public" or profile != "private":
        result.update(COLLABORATION_FILES)
    for overlay in config["overlays"]:
        result.update(OVERLAY_FILES[overlay])
    return result


def audit_generated_contract(config: dict[str, Any], expected: set[str], findings: list[Finding]) -> None:
    governance = config.get("governance")
    if not isinstance(governance, dict):
        return
    declared = governance.get("required_files")
    if governance.get("standard_version") != STANDARD_VERSION or governance.get("generator") != "Noetic QenTerra repository templates":
        findings.append(finding("GENERATED_METADATA_INVALID", "error", "Generated governance metadata does not match this checker."))
    if not isinstance(declared, list) or any(not isinstance(item, str) for item in declared):
        findings.append(finding("GENERATED_FILE_SET_INVALID", "error", "governance.required_files must be an array of paths."))
        return
    if len(declared) != len(set(declared)) or set(declared) != expected:
        findings.append(
            finding("GENERATED_FILE_SET_DRIFT", "error", "Generated required-file metadata differs from the embedded standard.")
        )


def audit_required_files(root: Path, expected: set[str], findings: list[Finding]) -> None:
    for relative in sorted(expected):
        path = root / relative
        if path.is_symlink() or (path.exists() and not path.resolve(strict=False).is_relative_to(root)):
            findings.append(finding("REQUIRED_FILE_UNSAFE", "error", "Required governance files must be contained regular files.", path=relative))
        elif not path.is_file():
            findings.append(finding("REQUIRED_FILE_MISSING", "error", "Selected composition requires this file.", path=relative))


def audit_content(root: Path, config: dict[str, Any], expected: set[str], findings: list[Finding]) -> None:
    for relative in sorted(expected):
        path = root / relative
        if not path.is_file():
            continue
        text = read_text(path)
        if text is not None and PLACEHOLDER_RE.search(text):
            findings.append(finding("TEMPLATE_PLACEHOLDER", "error", "File contains an unresolved template token.", path=relative))
        if text is not None and relative.endswith(".md") and DRAFT_MARKER in text:
            findings.append(finding("DRAFT_REVIEW_REQUIRED", "error", "Template still declares required project-specific review.", path=relative))

    readme = read_text(root / "README.md")
    if readme is not None:
        if f"# {config['project_name']}" not in readme:
            findings.append(finding("README_TITLE_INVALID", "error", "README title does not match project_name.", path="README.md"))
        for heading in README_HEADINGS[str(config["profile"])]:
            if heading not in readme:
                findings.append(finding("README_HEADING_MISSING", "error", f"README lacks {heading!r}.", path="README.md"))

    contact_targets = ["README.md"]
    if config["visibility"] == "public" or config["profile"] != "private":
        contact_targets.append("SUPPORT.md")
    for relative in contact_targets:
        text = read_text(root / relative)
        if text is None:
            continue
        if relative == "README.md":
            canonical = (
                "## Contact\n\n"
                f"- Product support, product help, and technical questions: [{SUPPORT_EMAIL}](mailto:{SUPPORT_EMAIL}).\n"
                f"- Proposals, general enquiries, and commercial matters: [{CONTACT_EMAIL}](mailto:{CONTACT_EMAIL}).\n"
                "- Vulnerabilities: follow the private reporting process in [SECURITY.md](SECURITY.md)."
            )
            if canonical not in text:
                findings.append(finding("README_CONTACT_BLOCK_INVALID", "error", "README must use the exact QenTerra Contact heading and three canonical bullets.", path=relative, remediation="Restore the canonical Contact block without project-specific prose inside it."))
        for code, email, purpose in (
            ("CONTACT_EMAIL_LINK_MISSING", CONTACT_EMAIL, "proposals, general enquiries, and commercial matters"),
            ("SUPPORT_EMAIL_LINK_MISSING", SUPPORT_EMAIL, "product support, help, and technical questions"),
        ):
            link = f"[{email}](mailto:{email})"
            if link not in text:
                findings.append(finding(code, "error", f"Canonical contact link for {purpose} is missing.", path=relative, remediation=f"Restore the exact active mail link {link}."))

    for relative in ("SECURITY.md", "CODE_OF_CONDUCT.md"):
        text = read_text(root / relative)
        if text is None:
            continue
        for email in (CONTACT_EMAIL, SUPPORT_EMAIL):
            if email in text:
                findings.append(finding("CONTACT_CHANNEL_SCOPE_VIOLATION", "error", f"Canonical mailbox {email!r} is being used in a private security or conduct route.", path=relative, remediation="Restore the separately configured private security or conduct contact."))

    changelog = read_text(root / "CHANGELOG.md")
    if changelog is not None and "## [Unreleased]" not in changelog:
        findings.append(finding("CHANGELOG_UNRELEASED_MISSING", "error", "CHANGELOG lacks an Unreleased section.", path="CHANGELOG.md"))

    license_id = str(config["license"])
    license_text = read_text(root / "LICENSE")
    if license_text is not None and LICENSE_MARKERS[license_id] not in license_text:
        findings.append(finding("LICENSE_TEXT_INVALID", "error", f"LICENSE does not match {license_id}.", path="LICENSE"))
    attribution_path = "LICENSE" if license_id in {"MIT", "Proprietary"} else "NOTICE"
    attribution = read_text(root / attribution_path)
    if attribution is not None and COPYRIGHT_HOLDER not in attribution:
        findings.append(finding("LICENSE_IDENTITY_MISSING", "error", "Legal attribution lacks the exact QenTerra holder.", path=attribution_path))


def audit_obsolete_funding_surfaces(root: Path, findings: list[Finding]) -> None:
    matches: set[str] = set()
    for path in iter_repository_paths(root):
        relative = path.relative_to(root).as_posix()
        if relative.casefold() == ".github/funding.yml":
            matches.add(relative)
        if not path.is_file() or path.is_symlink():
            continue
        text = read_text(path)
        if text is None:
            continue
        folded = text.casefold()
        if any(marker in folded for marker in OBSOLETE_FUNDING_MARKERS):
            matches.add(relative)
    for relative in sorted(matches):
        findings.append(finding("OBSOLETE_FUNDING_SURFACE_PROHIBITED", "error", "Repository contains an obsolete external-funding surface.", path=relative, remediation="Remove the funding configuration, link, badge, prose, product action, template, or test reference."))


def iter_repository_paths(root: Path) -> Iterable[Path]:
    for directory, names, files in os.walk(root, followlinks=False):
        names[:] = sorted(name for name in names if name != ".git")
        base = Path(directory)
        for name in names:
            yield base / name
        for name in sorted(files):
            yield base / name


def has_generated_header(path: Path) -> bool:
    lines: list[bytes] = []
    try:
        with path.open("rb") as handle:
            for _ in range(GENERATED_HEADER_LINE_COUNT):
                line = handle.readline(GENERATED_HEADER_LINE_MAX_BYTES + 1)
                if not line:
                    break
                if len(line) > GENERATED_HEADER_LINE_MAX_BYTES:
                    return decode_utf8_text(line, allow_incomplete_terminal=True) is not None
                lines.append(line)
    except OSError:
        return False
    decoded = decode_utf8_text(b"".join(lines))
    if decoded is None:
        return False
    header = decoded.casefold()
    return any(marker in header for marker in PUBLIC_GENERATED_HEADER_MARKERS)


def decode_utf8_text(
    content: bytes,
    *,
    allow_incomplete_terminal: bool = False,
) -> str | None:
    if b"\x00" in content:
        return None
    try:
        if allow_incomplete_terminal:
            decoder = codecs.getincrementaldecoder("utf-8")(errors="strict")
            decoded = decoder.decode(content, final=False)
        else:
            decoded = content.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if any(ord(character) < 32 and character not in "\t\n\r\f" for character in decoded):
        return None
    return decoded


def audit_portability(root: Path, config: dict[str, Any], expected: set[str], findings: list[Finding]) -> None:
    seen: dict[str, str] = {}
    for path in iter_repository_paths(root):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink() and not path.resolve(strict=False).is_relative_to(root):
            findings.append(finding("PATH_SYMLINK_ESCAPE", "error", "Symbolic link resolves outside the repository root.", path=relative))
        key = relative.casefold()
        if key in seen and seen[key] != relative:
            findings.append(finding("PATH_CASE_COLLISION", "error", f"Paths collide on case-insensitive filesystems: {seen[key]!r} and {relative!r}.", path=relative))
        seen[key] = relative
        for part in path.relative_to(root).parts:
            stem = part.split(".", 1)[0].upper()
            if part.endswith((" ", ".")) or stem in WINDOWS_RESERVED_NAMES or any(ord(char) < 32 for char in part):
                findings.append(finding("PATH_NOT_PORTABLE", "error", f"Path segment is not portable: {part!r}.", path=relative))

    allowed = set(DEFAULT_ROOT_PATHS) | set(config.get("allowed_root_paths", []))
    allowed.update(Path(relative).parts[0] for relative in expected)
    for path in sorted(root.iterdir(), key=lambda item: item.name.casefold()):
        name = path.name
        if name not in allowed:
            findings.append(finding("ROOT_PATH_UNDECLARED", "error", "Top-level path is neither standard nor declared by the contract.", path=name))
        if path.is_dir() and name not in DEFAULT_ROOT_PATHS and name not in set(config.get("allowed_root_paths", [])):
            if re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name) is None:
                findings.append(finding("ROOT_NAME_INVALID", "error", "General-purpose top-level directories use lowercase kebab-case.", path=name))


def audit_public_human_only_boundary(root: Path, config: dict[str, Any], findings: list[Finding]) -> None:
    if config.get("visibility") != "public":
        return

    agent_paths: set[str] = set()
    cache_paths: set[str] = set()
    undeclared_generated_paths: set[str] = set()
    declarations = config.get("published_artifacts", [])
    declared_roots = {
        str(item["path"]).rstrip("/")
        for item in declarations
        if isinstance(item, dict) and isinstance(item.get("path"), str)
    }

    for path in iter_repository_paths(root):
        relative = path.relative_to(root).as_posix()
        folded_relative = relative.casefold()
        parts = path.relative_to(root).parts
        folded = tuple(part.casefold() for part in parts)

        for index, part in enumerate(folded):
            if part in PUBLIC_AGENT_DIRECTORY_NAMES:
                agent_paths.add("/".join(parts[: index + 1]))
                break
        wrapped = "/" + folded_relative + "/"
        if any(
            folded_relative == prefix
            or folded_relative.startswith(prefix + "/")
            or ("/" + prefix + "/") in wrapped
            for prefix in PUBLIC_AGENT_PATH_PREFIXES
        ):
            agent_paths.add(relative)
        if folded and (
            folded[-1] in PUBLIC_AGENT_FILE_NAMES
            or any(fnmatch.fnmatchcase(folded[-1], pattern) for pattern in PUBLIC_AGENT_FILE_PATTERNS)
        ):
            agent_paths.add(relative)

        for index, part in enumerate(folded):
            if part in PUBLIC_CACHE_DIRECTORY_NAMES:
                cache_paths.add("/".join(parts[: index + 1]))
                break
        for prefix in PUBLIC_CACHE_PATH_PREFIXES:
            marker = "/" + prefix + "/"
            if folded_relative == prefix or folded_relative.startswith(prefix + "/") or marker in wrapped:
                start = folded_relative.find(prefix)
                cache_paths.add(relative[: start + len(prefix)])
                break
        if folded:
            filename = folded[-1]
            if (
                filename in PUBLIC_CACHE_FILE_NAMES
                or any(fnmatch.fnmatchcase(filename, pattern) for pattern in PUBLIC_CACHE_FILE_PATTERNS)
            ):
                cache_paths.add(relative)

        if path.is_file():
            declared = any(
                relative == declared_root or relative.startswith(declared_root + "/")
                for declared_root in declared_roots
            )
            generated_directory_member = False
            for index, part in enumerate(folded[:-1]):
                if part not in PUBLIC_GENERATED_DIRECTORY_NAMES:
                    continue
                generated_directory_member = True
                generated_root = "/".join(parts[: index + 1])
                if not declared:
                    undeclared_generated_paths.add(generated_root)
                break
            if not declared and not generated_directory_member and not path.is_symlink():
                if has_generated_header(path):
                    undeclared_generated_paths.add(relative)

    for relative in sorted(agent_paths):
        findings.append(finding(
            "PUBLIC_AGENT_ARTIFACT_PROHIBITED",
            "error",
            "Public repositories must not contain agent instructions, AI-tool state, prompts, transcripts, or skill bundles.",
            path=relative,
            remediation="Remove the artifact and keep agent work in a temporary directory outside the repository. This rule cannot be waived by contract exceptions.",
        ))
    for relative in sorted(cache_paths):
        findings.append(finding(
            "PUBLIC_CACHE_ARTIFACT_PROHIBITED",
            "error",
            "Public repositories must not contain caches, local environments, logs, coverage output, test output, or temporary build state.",
            path=relative,
            remediation="Delete the reproducible local artifact, add the matching ignore rule, and regenerate it outside the repository when possible. This rule cannot be waived by contract exceptions.",
        ))
    for relative in sorted(undeclared_generated_paths):
        findings.append(finding(
            "PUBLIC_GENERATED_ARTIFACT_UNDECLARED",
            "error",
            "Generated public distribution content is not declared by published_artifacts.",
            path=relative,
            remediation="Remove it or declare its consumer purpose, canonical source, manifest, verification command, and review trigger.",
        ))

    for artifact in declarations:
        if isinstance(artifact, dict):
            audit_published_artifact(root, artifact, findings)


def artifact_regular_files(root: Path, artifact_path: Path) -> tuple[list[Path], list[str]]:
    if artifact_path.is_file() and not artifact_path.is_symlink():
        return [artifact_path], []
    files: list[Path] = []
    unsafe: list[str] = []
    if not artifact_path.is_dir() or artifact_path.is_symlink():
        return files, unsafe
    for directory, names, filenames in os.walk(artifact_path, followlinks=False):
        base = Path(directory)
        for name in names:
            candidate = base / name
            if candidate.is_symlink():
                unsafe.append(candidate.relative_to(root).as_posix())
        for name in filenames:
            candidate = base / name
            relative = candidate.relative_to(root).as_posix()
            if candidate.is_symlink() or not candidate.resolve(strict=False).is_relative_to(root):
                unsafe.append(relative)
            elif candidate.is_file():
                files.append(candidate)
    return sorted(files), sorted(set(unsafe))


def git_path_tracked(root: Path, relative: str) -> bool | None:
    if not (root / ".git").exists():
        return None
    try:
        completed = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--error-unmatch", "--", relative],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return None
    if completed.returncode == 0:
        return True
    if completed.returncode == 1:
        return False
    return None


def safe_manifest_path(value: str) -> str | None:
    if not value or value.startswith(("/", "\\")) or "\\" in value:
        return None
    parts = value.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        return None
    return "/".join(parts)


def artifact_verification_entrypoint(value: str) -> str | None:
    if not isinstance(value, str) or not value.strip() or any(
        character in value for character in "\r\n;&|`$<>"
    ):
        return None
    try:
        tokens = shlex.split(value, posix=True)
    except ValueError:
        return None
    if not tokens:
        return None
    command = tokens[0].casefold()
    if command in {"bash", "node", "perl", "python", "python3", "ruby", "zsh"}:
        if len(tokens) < 2 or tokens[1].startswith("-"):
            return None
        candidate = tokens[1]
    else:
        candidate = tokens[0]
    if candidate.startswith("./"):
        candidate = candidate[2:]
    relative = safe_manifest_path(candidate)
    if (
        relative is None
        or not relative.casefold().startswith("scripts/")
        or not any(stem in Path(relative).name.casefold() for stem in ("audit", "check", "verify"))
    ):
        return None
    return relative


def audit_manifest_closure(
    root: Path,
    declared_path: str,
    tree_path: Path,
    manifest_entries: dict[str, tuple[str, int]],
    *,
    kind: str,
    findings: list[Finding],
) -> None:
    files, unsafe = artifact_regular_files(root, tree_path)
    label = "artifact" if kind == "ARTIFACT" else "source"
    for relative in unsafe:
        findings.append(finding(
            f"PUBLISHED_{kind}_PATH_UNSAFE",
            "error",
            f"Published {label} content contains a symbolic or escaped path.",
            path=relative,
        ))
    if not files:
        findings.append(finding(
            f"PUBLISHED_{kind}_EMPTY",
            "error",
            f"Declared public {label} contains no regular files.",
            path=declared_path,
        ))
        return
    actual_paths = {path.relative_to(root).as_posix() for path in files}
    root_relative = declared_path.rstrip("/")
    declared_paths = {
        relative
        for relative in manifest_entries
        if relative == root_relative or relative.startswith(root_relative + "/")
    }
    if actual_paths != declared_paths:
        findings.append(finding(
            f"PUBLISHED_{kind}_MANIFEST_DRIFT",
            "error",
            f"Published {label} files and checksum-manifest closure differ.",
            path=declared_path,
        ))
    for path in files:
        relative = path.relative_to(root).as_posix()
        expected = manifest_entries.get(relative)
        if expected is None:
            continue
        content = path.read_bytes()
        if hashlib.sha256(content).hexdigest() != expected[0] or len(content) != expected[1]:
            findings.append(finding(
                f"PUBLISHED_{kind}_DIGEST_MISMATCH",
                "error",
                f"Published {label} bytes do not match the checksum manifest.",
                path=relative,
            ))


def audit_published_artifact(root: Path, artifact: dict[str, Any], findings: list[Finding]) -> None:
    initial_errors = sum(item.severity == "error" for item in findings)
    paths = {key: root / str(artifact.get(key, "")) for key in ("path", "source", "manifest")}
    for key, code, message in (
        ("path", "PUBLISHED_ARTIFACT_PATH_MISSING", "Declared public artifact path is missing."),
        ("source", "PUBLISHED_ARTIFACT_SOURCE_MISSING", "Declared public artifact source is missing."),
        ("manifest", "PUBLISHED_ARTIFACT_MANIFEST_MISSING", "Declared public artifact manifest is missing."),
    ):
        candidate = paths[key]
        if not candidate.exists():
            findings.append(finding(code, "error", message, path=str(artifact.get(key, ""))))
        elif candidate.is_symlink() or not candidate.resolve(strict=False).is_relative_to(root):
            findings.append(finding(
                "PUBLISHED_ARTIFACT_PATH_UNSAFE",
                "error",
                "Published artifact declarations must resolve to contained non-symlink paths.",
                path=str(artifact.get(key, "")),
            ))
    if any(not candidate.exists() or candidate.is_symlink() for candidate in paths.values()):
        return
    if not paths["manifest"].is_file():
        findings.append(finding(
            "PUBLISHED_ARTIFACT_MANIFEST_INVALID",
            "error",
            "Published artifact manifest must be a regular JSON file.",
            path=str(artifact["manifest"]),
        ))
        return

    try:
        payload = json.loads(paths["manifest"].read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        payload = None
    entries = payload.get("files") if isinstance(payload, dict) else None
    if (
        not isinstance(payload, dict)
        or type(payload.get("schemaVersion")) is not int
        or payload.get("schemaVersion") != PUBLISHED_ARTIFACT_MANIFEST_SCHEMA_VERSION
        or not isinstance(entries, list)
    ):
        findings.append(finding(
            "PUBLISHED_ARTIFACT_MANIFEST_INVALID",
            "error",
            "Published artifact manifest must use schemaVersion 1 and contain a files array.",
            path=str(artifact["manifest"]),
        ))
        return

    manifest_entries: dict[str, tuple[str, int]] = {}
    invalid_manifest = False
    for entry in entries:
        if (
            not isinstance(entry, dict)
            or not isinstance(entry.get("path"), str)
            or re.fullmatch(r"[0-9a-f]{64}", str(entry.get("sha256", ""))) is None
            or type(entry.get("bytes")) is not int
            or entry["bytes"] < 0
        ):
            invalid_manifest = True
            continue
        relative = safe_manifest_path(entry["path"])
        if relative is None or relative in manifest_entries:
            invalid_manifest = True
            continue
        manifest_entries[relative] = (entry["sha256"], entry["bytes"])
    if invalid_manifest:
        findings.append(finding(
            "PUBLISHED_ARTIFACT_MANIFEST_INVALID",
            "error",
            "Published artifact manifest contains malformed, unsafe, or duplicate file records.",
            path=str(artifact["manifest"]),
        ))

    entrypoint = artifact_verification_entrypoint(str(artifact.get("verification_command", "")))
    verifier = root / entrypoint if entrypoint is not None else None
    if (
        verifier is None
        or not verifier.is_file()
        or verifier.is_symlink()
        or not verifier.resolve(strict=False).is_relative_to(root)
    ):
        findings.append(finding(
            "PUBLISHED_ARTIFACT_VERIFIER_INVALID",
            "error",
            "Published artifact verification must invoke an existing contained versioned scripts/ entrypoint.",
            path=str(artifact.get("verification_command", "")),
        ))
    elif entrypoint is not None:
        tracked = git_path_tracked(root, entrypoint)
        if tracked is False:
            findings.append(finding(
                "PUBLISHED_ARTIFACT_VERIFIER_UNTRACKED",
                "error",
                "Published artifact verifier exists locally but is not tracked by Git.",
                path=entrypoint,
            ))
        elif tracked is None:
            findings.append(finding(
                "PUBLISHED_ARTIFACT_VERIFIER_TRACKING_UNVERIFIED",
                "unverified",
                "The verifier exists, but this source has no readable Git index proving that it is versioned.",
                path=entrypoint,
            ))

    audit_manifest_closure(
        root,
        str(artifact["source"]),
        paths["source"],
        manifest_entries,
        kind="SOURCE",
        findings=findings,
    )
    audit_manifest_closure(
        root,
        str(artifact["path"]),
        paths["path"],
        manifest_entries,
        kind="ARTIFACT",
        findings=findings,
    )
    if sum(item.severity == "error" for item in findings) == initial_errors:
        findings.append(finding(
            "PUBLISHED_ARTIFACT_REGENERATION_UNVERIFIED",
            "unverified",
            "Static audit verified source and artifact checksum closure but did not execute the declared regeneration verifier.",
            path=str(artifact["verification_command"]),
            remediation="Run the declared verifier in an isolated temporary checkout and record its exact result separately.",
        ))


def audit_documentation_names(root: Path, findings: list[Finding]) -> None:
    docs = root / "docs"
    if not docs.is_dir():
        return
    for path in sorted(docs.rglob("*"), key=lambda item: item.as_posix().casefold()):
        relative = path.relative_to(root).as_posix()
        if path.is_file() and path.suffix == ".md":
            section = path.relative_to(docs).parts[0]
            if section in {"assets", "decisions", "wiki"}:
                continue
            if re.fullmatch(r"(?:README|[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)\.md", path.name) is None:
                findings.append(finding("DOC_NAME_INVALID", "error", "Maintained docs use uppercase snake-case filenames or README.md.", path=relative))
        elif path.is_dir() and path.relative_to(docs).parts[0] != "assets":
            if re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", path.name) is None:
                findings.append(finding("DOC_DIRECTORY_NAME_INVALID", "error", "General documentation directories use lowercase kebab-case.", path=relative))

    decisions = docs / "decisions"
    if decisions.is_dir():
        for path in sorted(decisions.rglob("*.md"), key=lambda item: item.as_posix().casefold()):
            if path != decisions / "README.md" and re.fullmatch(r"\d{4}-[a-z0-9]+(?:-[a-z0-9]+)*\.md", path.name) is None:
                findings.append(finding("ADR_NAME_INVALID", "error", "Architecture decisions use a four-digit sequence and lowercase kebab-case title.", path=path.relative_to(root).as_posix()))

    assets = docs / "assets"
    if assets.is_dir():
        for path in sorted(assets.rglob("*"), key=lambda item: item.as_posix().casefold()):
            relative = path.relative_to(root).as_posix()
            if path.is_dir():
                if re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", path.name) is None:
                    findings.append(finding("ASSET_DIRECTORY_NAME_INVALID", "error", "Documentation asset directories use lowercase kebab-case.", path=relative))
            elif re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*(?:\.[a-z0-9]+)+", path.name) is None:
                findings.append(finding("ASSET_NAME_INVALID", "error", "Documentation assets use descriptive lowercase kebab-case filenames.", path=relative))


def wiki_target(link: str) -> str | None:
    clean = unquote(link.strip().split("#", 1)[0])
    if not clean or clean.startswith(("#", "/")) or "://" in clean or clean.startswith("mailto:"):
        return None
    return clean[:-3] if clean.endswith(".md") else clean


def audit_wiki(root: Path, config: dict[str, Any], findings: list[Finding]) -> None:
    if "github-wiki" not in config["overlays"]:
        return
    wiki = root / "docs/wiki"
    pages = {path.stem: path for path in wiki.glob("*.md") if path.is_file()} if wiki.is_dir() else {}
    sidebar_targets: set[str] = set()
    for stem, path in sorted(pages.items()):
        if stem not in {"Home", "_Sidebar", "_Footer"} and re.fullmatch(r"[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*", stem) is None:
            findings.append(finding("WIKI_PAGE_NAME_INVALID", "error", "Wiki pages use Title-Case-with-Hyphens.md.", path=path.relative_to(root).as_posix()))
    for stem, path in sorted(pages.items()):
        text = read_text(path) or ""
        for raw_link in MARKDOWN_LINK_RE.findall(text):
            target = wiki_target(raw_link)
            if target is None:
                continue
            target_name = Path(target).name
            if stem == "_Sidebar":
                sidebar_targets.add(target_name)
            if target_name not in pages:
                findings.append(finding("WIKI_LINK_BROKEN", "error", f"Wiki target does not exist: {raw_link!r}.", path=path.relative_to(root).as_posix()))
    if "_Sidebar" not in pages:
        findings.append(finding("WIKI_SIDEBAR_MISSING", "error", "Wiki has no _Sidebar.md.", path="docs/wiki/_Sidebar.md"))
        return
    for stem, path in sorted(pages.items()):
        if stem not in {"_Sidebar", "_Footer", "Home"} and stem not in sidebar_targets:
            findings.append(finding("WIKI_PAGE_ORPHAN", "error", "Wiki page is not reachable from the sidebar.", path=path.relative_to(root).as_posix()))


def markdown_target(root: Path, source: Path, raw_link: str) -> Path | None:
    clean = unquote(raw_link.strip().split("#", 1)[0])
    if not clean or clean.startswith("#") or "://" in clean or clean.startswith(("mailto:", "tel:")):
        return None
    if clean.startswith("/"):
        return root / clean.lstrip("/")
    return (source.parent / clean).resolve(strict=False)


def audit_local_markdown_links(root: Path, expected: set[str], findings: list[Finding]) -> None:
    for relative in sorted(path for path in expected if path.endswith(".md") and not path.startswith("docs/wiki/")):
        source = root / relative
        text = read_text(source)
        if text is None:
            continue
        for raw_link in MARKDOWN_LINK_RE.findall(text):
            target = markdown_target(root, source, raw_link)
            if target is None:
                continue
            if not target.is_relative_to(root) or not target.exists():
                findings.append(finding("MARKDOWN_LINK_BROKEN", "error", f"Local Markdown target does not exist: {raw_link!r}.", path=relative))


def audit_workflows(root: Path, findings: list[Finding]) -> None:
    workflow_root = root / ".github/workflows"
    if not workflow_root.is_dir():
        return
    for path in sorted((*workflow_root.glob("*.yml"), *workflow_root.glob("*.yaml"))):
        text = read_text(path)
        relative = path.relative_to(root).as_posix()
        if text is None:
            continue
        if re.search(r"^pull_request_target\s*:", text, re.MULTILINE):
            findings.append(finding("WORKFLOW_PULL_REQUEST_TARGET", "error", "pull_request_target requires a separately reviewed threat model.", path=relative))
        if re.search(r"^permissions\s*:", text, re.MULTILINE) is None:
            findings.append(finding("WORKFLOW_PERMISSIONS_MISSING", "error", "Workflow has no explicit top-level permissions.", path=relative))
        if path.name == "repository-governance.yml":
            if "fetch-depth: 0" not in text:
                findings.append(finding("WORKFLOW_CHECKOUT_HISTORY_INCOMPLETE", "error", "Governance workflow does not fetch enough history to check the actual change range.", path=relative))
            if "persist-credentials: false" not in text:
                findings.append(finding("WORKFLOW_CHECKOUT_CREDENTIALS_PERSISTED", "error", "Governance checkout must not persist write credentials.", path=relative))
            required_diff_tokens = (
                'git diff --check "$BASE_SHA...HEAD"',
                'git diff --check "$BEFORE_SHA..HEAD"',
                "git diff --check 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD",
            )
            if any(token not in text for token in required_diff_tokens):
                findings.append(finding("WORKFLOW_DIFF_RANGE_MISSING", "error", "Governance workflow does not check pull-request, push, and initial-history ranges.", path=relative))
            if "if: always()" not in text or "repository-governance-report.md" not in text:
                findings.append(finding("WORKFLOW_REPORT_NOT_PRESERVED", "error", "Governance workflow does not preserve its report after failures.", path=relative))
            if '--output "$RUNNER_TEMP/repository-governance-report.md"' not in text or "path: ${{ runner.temp }}/repository-governance-report.md" not in text:
                findings.append(finding("WORKFLOW_REPORT_INSIDE_REPOSITORY", "error", "Governance reports must be written and uploaded from the runner temporary directory, not the repository checkout.", path=relative))
        for use in ACTION_USE_RE.findall(text):
            if use.startswith(("./", "docker://")):
                continue
            reference = use.rsplit("@", 1)[1] if "@" in use else ""
            if PINNED_SHA_RE.fullmatch(reference) is None:
                findings.append(finding("ACTION_REF_UNPINNED", "error", f"Action is not pinned to a full commit SHA: {use!r}.", path=relative))


def audit_repository(root: Path) -> dict[str, Any]:
    root = root.resolve()
    findings: list[Finding] = []
    config: dict[str, Any] | None = None
    expected: set[str] = set()
    checked_scope = ["repository-contract"]
    if not root.is_dir():
        findings.append(finding("REPOSITORY_ROOT_MISSING", "error", "Repository root is missing or not a directory."))
    else:
        config = load_config(root, findings)
    if config is not None and validate_contract(config, findings):
        checked_scope.extend(
            [
                "required-files",
                "identity-and-license",
                "contact-channels",
                "obsolete-funding-surfaces",
                "root-naming",
                "readme-and-changelog",
                "path-portability",
                "public-human-only-boundary",
                "documentation-naming",
                "local-markdown-links",
                "template-residue",
                "version",
                "wiki-topology",
                "workflow-hardening",
                "external-settings-evidence",
            ]
        )
        expected = expected_files(config)
        audit_generated_contract(config, expected, findings)
        audit_required_files(root, expected, findings)
        audit_content(root, config, expected, findings)
        audit_obsolete_funding_surfaces(root, findings)
        audit_portability(root, config, expected, findings)
        audit_public_human_only_boundary(root, config, findings)
        audit_documentation_names(root, findings)
        audit_wiki(root, config, findings)
        audit_local_markdown_links(root, expected, findings)
        audit_workflows(root, findings)
        findings.append(
            finding(
                "EXTERNAL_GITHUB_SETTINGS_UNVERIFIED",
                "unverified",
                "Live GitHub rulesets, repository features, security settings, Wiki projection, releases, assets, and links were not inspected by this local audit.",
                remediation="Run and record an authorised GitHub API or settings review for the exact repository.",
            )
        )
    findings = sorted_findings(findings)
    counts = {
        "errors": sum(item.severity == "error" for item in findings),
        "warnings": sum(item.severity == "warning" for item in findings),
        "unverified": sum(item.severity == "unverified" for item in findings),
    }
    result = "failed" if counts["errors"] else "passed-with-unverified" if counts["unverified"] else "passed-with-warnings" if counts["warnings"] else "passed"
    return {
        "result": result,
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "tool_version": TOOL_VERSION,
        "standard_version": config.get("standard_version") if config else None,
        "repository_root": str(root),
        "profile": config.get("profile") if config else None,
        "overlays": config.get("overlays", []) if config else [],
        "visibility": config.get("visibility") if config else None,
        "license": config.get("license") if config else None,
        "version_scheme": config.get("version_scheme") if config else None,
        "checked_scope": checked_scope,
        "counts": counts,
        "findings": [item.to_dict() for item in findings],
    }


def format_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Repository governance report",
        "",
        f"- Result: `{report['result']}`",
        f"- Tool: `{report['tool_version']}`",
        f"- Standard: `{report['standard_version'] or 'unknown'}`",
        f"- Profile: `{report['profile'] or 'unknown'}`",
        f"- Repository: `{report['repository_root']}`",
        f"- Generated: `{report['generated_at']}`",
        "",
        "## Counts",
        "",
        f"- Errors: {report['counts']['errors']}",
        f"- Warnings: {report['counts']['warnings']}",
        f"- Unverified: {report['counts']['unverified']}",
        "",
        "## Findings",
        "",
    ]
    if not report["findings"]:
        lines.append("No findings.")
    for item in report["findings"]:
        location = f" in `{item['path']}`" if item.get("path") else ""
        lines.append(f"- **{item['severity'].title()} `{item['code']}`**{location}: {item['message']}")
        if item.get("remediation"):
            lines.append(f"  Remediation: {item['remediation']}")
    lines.extend(
        [
            "",
            "## Evidence boundary",
            "",
            "A clean local audit does not prove live GitHub settings, legal sufficiency, release assets, signatures, deployments, accessibility, or product behaviour. Those surfaces remain Unverified until separately inspected.",
            "",
        ]
    )
    return "\n".join(lines)


def write_output(value: str, output: Path | None) -> None:
    if output is None:
        print(value, end="" if value.endswith("\n") else "\n")
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(value if value.endswith("\n") else value + "\n", encoding="utf-8")


def finding_report(subject: str, findings: list[Finding]) -> dict[str, Any]:
    ordered = sorted_findings(findings)
    return {
        "result": "failed" if any(item.severity == "error" for item in ordered) else "passed",
        "subject": subject,
        "tool_version": TOOL_VERSION,
        "findings": [item.to_dict() for item in ordered],
    }


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    commands = value.add_subparsers(dest="command", required=True)
    audit = commands.add_parser("audit")
    audit.add_argument("--root", type=Path, required=True)
    audit.add_argument("--format", choices=("json", "markdown"), default="json")
    audit.add_argument("--output", type=Path)
    commit = commands.add_parser("commit-message")
    commit.add_argument("--message", required=True)
    commit.add_argument("--format", choices=("json", "markdown"), default="json")
    commit.add_argument("--output", type=Path)
    version = commands.add_parser("version")
    version.add_argument("--value", required=True)
    version.add_argument("--scheme", choices=("semver", "calver"), required=True)
    version.add_argument("--format", choices=("json", "markdown"), default="json")
    version.add_argument("--output", type=Path)
    branch = commands.add_parser("branch")
    branch.add_argument("--value", required=True)
    branch.add_argument("--format", choices=("json", "markdown"), default="json")
    branch.add_argument("--output", type=Path)
    return value


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    if args.command == "audit":
        report = audit_repository(args.root)
        rendered = json.dumps(report, indent=2, ensure_ascii=False) if args.format == "json" else format_markdown(report)
        write_output(rendered, args.output)
        return 1 if report["counts"]["errors"] else 0
    if args.command == "commit-message":
        findings = validate_commit_message(args.message)
        subject = "commit-message"
    elif args.command == "version":
        findings = validate_version(args.value, args.scheme)
        subject = "version"
    else:
        findings = validate_branch_name(args.value)
        subject = "branch"
    report = finding_report(subject, findings)
    if args.format == "json":
        rendered = json.dumps(report, indent=2, ensure_ascii=False)
    else:
        rendered = f"# {report['subject']} report\n\nResult: `{report['result']}`\n"
        for item in report["findings"]:
            rendered += f"\n- **{item['severity'].title()} `{item['code']}`**: {item['message']}"
        rendered += "\n"
    write_output(rendered, args.output)
    return 1 if report["result"] == "failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())
