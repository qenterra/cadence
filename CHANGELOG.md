# Changelog

Cadence follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-12

Cadence 1.0.0 (build 3) supports Apple silicon Macs running macOS 26 or later.
This release is a manual download with an ad-hoc signature; it is not
Developer ID signed or notarized and is not delivered through Sparkle. See the
[installation guide](README.md#install-cadence) for Gatekeeper instructions.

### Added

- Advanced playback, library, notification, and interface settings.
- An artwork-colored Metal background in Cadence Mode with smooth track-color
  transitions and activity-aware tinting for keyboard effects.

### Changed

- Separated Home favorites into tracks, albums, and artists.
- Adopted shared native table cells, artwork gradients, and interface components
  from QenTerra Design System while retaining Cadence's library and playback behavior.
- Reused independent QenTerraFoundation and QenTerraAudioAnalysis products for
  hashing, text, caches, pagination, image processing, media clocks, and PCM analysis.
- Updated GRDB to 7.11.1 and AppAuth to 3.0.0.
- Updated contributor guides and canonical Wiki sources for the current app and
  release process.

### Removed

- Unused interface declarations and unreachable remote-library write APIs;
  configured remote libraries remain readable.
- Obsolete external donation configuration.
- The Sparkle entry for the retired beta download.

### Fixed

- Kept favorite tracks visible in Recently Played as well as Favorites.
- Corrected track-row playback indicators and aligned year, duration, and options
  controls in track tables.
- Applied inactive-line blur to lyrics without blurring track titles.
- Removed dark backgrounds from About resource links, the selected-track outline,
  and the current-track queue decoration.
- Kept automatic library maintenance out of preview sessions so retention settings
  cannot erase fixture history or interrupt previews with library alerts.

## [0.2.0-beta.1] - 2026-08-13

### Added

- Added temporary Finder playback for supported audio files without automatic
  library import, plus an explicit **Add to Library…** action for the current
  external track.
- Added the first installable Apple silicon beta as a styled monochrome DMG,
  a Sparkle update archive, and SHA-256 checksums.
- Added one manifest-backed release version contract across Xcode, Git tags,
  documentation, archive names, signing claims, and installer metadata.

### Changed

- Updated Cadence to QenTerra Design System 4.1.0.
- Registered supported audio formats as Viewer document types while keeping
  manual library import as the only persistence path.

## [0.1.0] - 2026-07-31

### Added

- Managed `Cadence.library` import, duplicate review, LRC matching, and
  recoverable Trash.
- Native playback coordination, queue management, media controls, output-route
  reporting, and audio quality profiles.
- Library views for tracks, albums, artists, tags, playlists, smart
  collections, Now Playing, search, and settings.
- Line-timed lyrics, Lyrics Editor, artwork editing, contextual navigation, and
  light, dark, and system appearance modes.
- SwiftData persistence and a unit and integration test suite.

[Unreleased]: https://github.com/QenTerra/cadence/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/QenTerra/cadence/releases/tag/v1.0.0
[0.2.0-beta.1]: https://github.com/QenTerra/cadence/tree/730f61fe837493d550f335edb0ded97d5c19562a
[0.1.0]: https://github.com/QenTerra/cadence/tree/main
