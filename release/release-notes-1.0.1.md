Cadence 1.0.1 fixes a crash in optimized builds when sorting library tracks by
album or year.

## Fixed

- Replaced SwiftData relationship-traversing sort descriptors for the Album and
  Year columns with Cadence-owned stable ordering after a safe fetch.
- Preserved global pagination and virtual track-window ordering when album names
  are equal or album and year metadata are missing.

## Downloads

Version **1.0.1** requires an Apple silicon Mac running macOS 26 or later.

- [Cadence-1.0.1-arm64.dmg](https://github.com/QenTerra/cadence/releases/download/v1.0.1/Cadence-1.0.1-arm64.dmg) — open the DMG and drag Cadence to Applications.
- [Cadence-1.0.1-arm64.zip](https://github.com/QenTerra/cadence/releases/download/v1.0.1/Cadence-1.0.1-arm64.zip) — alternative application archive.
- [Cadence-1.0.1-SHA256SUMS.txt](https://github.com/QenTerra/cadence/releases/download/v1.0.1/Cadence-1.0.1-SHA256SUMS.txt) — checksums for the downloads.

The app is **ad-hoc signed, not Developer ID signed, and not notarized**.
Gatekeeper may block its first launch. If you trust the official download, use
**Open Anyway** for Cadence in **System Settings > Privacy & Security** after
the blocked launch. Follow [Apple's instructions](https://support.apple.com/en-gb/102445).

This release is a manual download and is not delivered through Sparkle.

## Known issues

- Intel and universal binaries are not included.
- Hardware-specific output routes, extended playback, VoiceOver, and Cadence
  Mode frame pacing require manual acceptance on the target Mac.

## Verification

The source release gate covers the Xcode build and tests, localization,
formatting and linting, dependency ownership, and release-contract checks. A
release-optimized persistent-store regression covers album and year sorting,
including equal and missing metadata.

Those automated checks do not establish Developer ID identity, notarization,
or acceptance across all supported hardware and assistive technologies.

## Full changelog

[Cadence changelog](https://github.com/QenTerra/cadence/blob/v1.0.1/CHANGELOG.md#101---2026-09-17).
