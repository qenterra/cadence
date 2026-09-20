# Changelog

Cadence follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1] - 2026-09-20

### Fixed

- Prevented optimized builds from crashing when the track table is sorted by
  album or year. Cadence now applies those relationship-backed orders itself
  after a safe SwiftData fetch, preserving stable pagination for equal or
  missing album metadata.

### Distribution

- Published the unchanged 1.0.1 update archive through Cadence's EdDSA-signed
  Sparkle feed. The app remains ad-hoc signed and not notarized.

## [1.0.0] - 2026-09-13

The first public release of Cadence, a native macOS music player and library
manager for local collections.

Cadence 1.0.0 supports Apple silicon Macs running macOS 26 or later.
The app is ad-hoc signed and not notarized. See the
[installation guide](README.md#install-cadence) for download and Gatekeeper
instructions.

### Added

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

[Unreleased]: https://github.com/QenTerra/cadence/compare/v1.0.1...main
[1.0.1]: https://github.com/QenTerra/cadence/releases/tag/v1.0.1
[1.0.0]: https://github.com/QenTerra/cadence/releases/tag/v1.0.0
