Cadence 1.0.3 makes library editing more dependable, tidies Home, and closes several playback and import failures.

## Added

- Edit a managed track's title, artist, album, and year from one sheet. Cadence updates the managed audio file and refreshes every library view.
- Add descriptions to artists, playlists, and Smart Collections.
- Edit artists, albums, tracks, tags, playlists, and Smart Collections from consistent detail-page controls.
- Show tags on Home and control Home section order in Settings.

## Changed

- Removed Smart Collection cards from Home. Smart Collections remain available in their dedicated browser and detail pages.
- Favorite Tracks on Home uses the standard track list, including its favorite control, while favorite albums and artists use horizontal shelves.
- Playlists, Smart Collections, and tags can share one saved list width or keep individual widths.
- Enlarged the window-wide import drop target and redesigned the track picker shared by playlists and tags.
- Standardized catalog context menus and artwork actions.

## Fixed

- Prevented Shuffle from crashing on a one-track album or collection.
- Smart Collection edits now save before deferred navigation continues.
- Closing the AirPlay picker no longer focuses Search.
- Track metadata edits now refresh lists instead of changing only Now Playing.
- Playback artwork no longer keeps animating after a track or queue ends.
- Empty-library placeholders stay centered across library pages.

## Downloads

Version **1.0.3** requires an Apple silicon Mac running macOS 26 or later.

- [Cadence-1.0.3-arm64.dmg](https://github.com/QenTerra/cadence/releases/download/v1.0.3/Cadence-1.0.3-arm64.dmg) — open the DMG and drag Cadence to Applications.
- [Cadence-1.0.3-arm64.zip](https://github.com/QenTerra/cadence/releases/download/v1.0.3/Cadence-1.0.3-arm64.zip) — alternative application archive and Sparkle update.
- [Cadence-1.0.3-SHA256SUMS.txt](https://github.com/QenTerra/cadence/releases/download/v1.0.3/Cadence-1.0.3-SHA256SUMS.txt) — checksums for the downloads.

The app is **ad-hoc signed, not Developer ID signed, and not notarized**. Gatekeeper may block its first launch. If you trust the official download, use **Open Anyway** for Cadence in **System Settings > Privacy & Security** after the blocked launch. Follow [Apple's instructions](https://support.apple.com/en-gb/102445).

Initial installation uses the manual download. Existing Cadence installations can verify and install this release through the EdDSA-signed Sparkle feed.

## Known issues

- Intel and universal binaries are not included.
- Hardware-specific output routes, extended playback, VoiceOver, and Cadence Mode frame pacing require manual acceptance on the target Mac.

## Verification

The source release gate covers the Xcode build and tests, localization, formatting and linting, dependency ownership, dead-code analysis, and release-contract checks. Visual acceptance remains a separate manual check on the target Mac.

Sparkle's EdDSA signature authenticates the update archive but does not establish Developer ID identity or notarization. Automated checks do not establish acceptance across all supported hardware and assistive technologies.

## Full changelog

[Compare Cadence 1.0.2...1.0.3](https://github.com/QenTerra/cadence/compare/v1.0.2...v1.0.3).
