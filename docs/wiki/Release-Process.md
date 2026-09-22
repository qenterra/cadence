# Release Process

Releases use `semver`, the version source `release-contract.json`, curated changelog entries, exact revision verification, profile-specific artifact checks, and post-publication remote verification.

The current public release is Cadence 1.0.2, tag `v1.0.2`, for Apple silicon
and macOS 26 or later. This release uses the disclosed ad-hoc public
distribution profile: DMG, Sparkle-signed ZIP, appcast, and SHA-256 checksums.
It is not notarized. Sparkle EdDSA signing authenticates the update archive;
Developer ID and notarization remain a separate future distribution profile.

Read the canonical [release guide](https://github.com/QenTerra/cadence/blob/main/docs/RELEASING.md) and [changelog](https://github.com/QenTerra/cadence/blob/main/CHANGELOG.md).
