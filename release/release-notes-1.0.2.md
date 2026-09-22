Cadence 1.0.2 centers the bottom player and makes settings and everyday text easier to scan.

## Changed

- Reorganized Settings into General, Playback, Library, Interface, Shortcuts, Updates, Advanced, and About.
- Shortened labels, empty states, import guidance, alerts, and supporting text throughout the app.

## Fixed

- Centered the controls vertically in the bottom player.

## Downloads

Version **1.0.2** requires an Apple silicon Mac running macOS 26 or later.

- [Cadence-1.0.2-arm64.dmg](https://github.com/QenTerra/cadence/releases/download/v1.0.2/Cadence-1.0.2-arm64.dmg) — open the DMG and drag Cadence to Applications.
- [Cadence-1.0.2-arm64.zip](https://github.com/QenTerra/cadence/releases/download/v1.0.2/Cadence-1.0.2-arm64.zip) — alternative application archive and Sparkle update.
- [Cadence-1.0.2-SHA256SUMS.txt](https://github.com/QenTerra/cadence/releases/download/v1.0.2/Cadence-1.0.2-SHA256SUMS.txt) — checksums for the downloads.

The app is **ad-hoc signed, not Developer ID signed, and not notarized**. Gatekeeper may block its first launch. If you trust the official download, use **Open Anyway** for Cadence in **System Settings > Privacy & Security** after the blocked launch. Follow [Apple's instructions](https://support.apple.com/en-gb/102445).

Initial installation uses the manual download. Existing Cadence installations can verify and install this release through the EdDSA-signed Sparkle feed.

## Known issues

- Intel and universal binaries are not included.
- Hardware-specific output routes, extended playback, VoiceOver, and Cadence Mode frame pacing require manual acceptance on the target Mac.

## Verification

The source release gate covers the Xcode build and tests, localization, formatting and linting, dependency ownership, and release-contract checks. Visual acceptance tests cover the bottom player and the reorganized settings in System, Light, and Dark appearances.

Sparkle's EdDSA signature authenticates the update archive but does not establish Developer ID identity or notarization. Automated checks do not establish acceptance across all supported hardware and assistive technologies.

## Full changelog

[Compare Cadence 1.0.1...1.0.2](https://github.com/QenTerra/cadence/compare/v1.0.1...v1.0.2).
