The first public release of Cadence, a native macOS music player and library manager for local collections.

## Added

- Managed local music library with file and folder import, duplicate review,
  preserved source files, and recoverable Trash.
- Temporary playback of AAC, AIFF, FLAC, M4A, MP3, and WAV files opened from
  Finder, with an explicit action to add them to the library.
- Native playback, queue management, media-key controls, and audio format and
  output-route information.
- Library views for tracks, albums, artists, playlists, and smart collections,
  with separate favorite tracks, albums, and artists on Home.
- Search, hierarchical tags, and nested smart-collection rules for organizing
  music without rewriting source audio files.
- Line-timed LRC lyrics, seeking from a lyric line, and a built-in Lyrics Editor.
- Track, album, and artist artwork import, cropping, and editing.
- Cadence Mode with an artwork-colored animated background and keyboard effects.
- System, light, and dark appearance, plus playback, library, notification,
  and interface settings.
- Optional WebDAV and Google Drive library reading, configured explicitly in
  Settings; local playback requires no account.

## Downloads

Requires an Apple silicon Mac running macOS 26 or later. Settings shows
**1.0.0 (build 3)**.

- [Cadence-1.0.0-arm64.dmg](https://github.com/QenTerra/cadence/releases/download/v1.0.0/Cadence-1.0.0-arm64.dmg) — open the DMG and drag Cadence to Applications.
- [Cadence-1.0.0-arm64.zip](https://github.com/QenTerra/cadence/releases/download/v1.0.0/Cadence-1.0.0-arm64.zip) — alternative application archive.
- [Cadence-1.0.0-SHA256SUMS.txt](https://github.com/QenTerra/cadence/releases/download/v1.0.0/Cadence-1.0.0-SHA256SUMS.txt) — checksums for the downloads.

Launch Cadence, choose a managed library folder, and import your music.
The app keeps the original audio files untouched.

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

[Cadence 1.0.0 — first release](https://github.com/QenTerra/cadence/releases/tag/v1.0.0).
