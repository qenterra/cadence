Cadence 1.0.0 brings separate Home favorites, shared native interface components, and an artwork-colored Cadence Mode to the local macOS music player.

## Upgrade notes

Requires an Apple silicon Mac running macOS 26 or later. Settings identifies
this release as **1.0.0 (build 3)**.

Install this version manually: quit Cadence, open the DMG, and drag Cadence to
Applications. This release is not delivered through the in-app updater. Keep a backup of your managed Cadence
folder and the app's Application Support data before upgrading an existing
library; the catalog and managed media are stored separately.

## Added

- Advanced playback, library, notification, and interface settings.
- An artwork-colored Metal background in Cadence Mode with smooth track-color
  transitions and activity-aware tinting for keyboard effects.

## Changed

- Separated Home favorites into tracks, albums, and artists.
- Adopted shared native table cells, artwork gradients, and interface components
  from QenTerra Design System while retaining Cadence's library and playback behavior.
- Reused independent QenTerraFoundation and QenTerraAudioAnalysis products for
  hashing, text, caches, pagination, image processing, media clocks, and PCM analysis.
- Updated GRDB to 7.11.1 and AppAuth to 3.0.0.
- Updated contributor guides and canonical Wiki sources for the current app and
  release process.

## Removed

- Unused interface declarations and unreachable remote-library write APIs;
  configured remote libraries remain readable.
- Obsolete external donation configuration.
- The Sparkle entry for the retired beta download.

## Fixed

- Kept favorite tracks visible in Recently Played as well as Favorites.
- Corrected track-row playback indicators and aligned year, duration, and options
  controls in track tables.
- Applied inactive-line blur to lyrics without blurring track titles.
- Removed dark backgrounds from About resource links, the selected-track outline,
  and the current-track queue decoration.
- Kept automatic library maintenance out of preview sessions so retention settings
  cannot erase fixture history or interrupt previews with library alerts.

## Downloads

- [Cadence-1.0.0-arm64.dmg](https://github.com/QenTerra/cadence/releases/download/v1.0.0/Cadence-1.0.0-arm64.dmg) — drag-to-Applications installer.
- [Cadence-1.0.0-arm64.zip](https://github.com/QenTerra/cadence/releases/download/v1.0.0/Cadence-1.0.0-arm64.zip) — alternative manual application archive; not a Sparkle update.
- [Cadence-1.0.0-SHA256SUMS.txt](https://github.com/QenTerra/cadence/releases/download/v1.0.0/Cadence-1.0.0-SHA256SUMS.txt) — checksums for the binary downloads.

The app is **ad-hoc signed, not Developer ID signed, and not notarized**.
Gatekeeper may block its first launch. If you trust the official download,
use **Open Anyway** for Cadence in **System Settings > Privacy & Security**
after the blocked launch. Follow [Apple's instructions](https://support.apple.com/en-gb/102445).

## Known issues

- Intel and universal binaries are not included.
- Hardware-specific output routes, extended playback, VoiceOver, and
  Cadence Mode frame pacing require manual acceptance on the target Mac.

## Verification

The source release gate covers the Xcode build and tests, localization,
formatting and linting, dependency ownership, and release-contract checks.
Those automated checks do not establish Developer ID identity, notarization,
or acceptance across all supported hardware and assistive technologies.

## Full changelog

[Cadence 1.0.0 changelog](https://github.com/QenTerra/cadence/blob/v1.0.0/CHANGELOG.md#100---2026-09-12).
