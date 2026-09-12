# Release Process

Releases use `semver`, the version source `release-contract.json`, curated changelog entries, exact revision verification, profile-specific artifact checks, and post-publication remote verification.

The current contract is Cadence 1.0.0 (build 3), tag `v1.0.0`, for Apple
silicon and macOS 26 or later. This release uses the disclosed ad-hoc manual
distribution profile: DMG, manual ZIP, and SHA-256 checksums. It is not
notarized and is not delivered through Sparkle. The obsolete beta appcast
entry has been removed. The Developer ID and
notarization workflow remains a separate distribution profile.

Read the canonical [release guide](https://github.com/QenTerra/cadence/blob/main/docs/RELEASING.md) and [changelog](https://github.com/QenTerra/cadence/blob/main/CHANGELOG.md).
