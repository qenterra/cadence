# Changelog

Cadence follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added advanced playback, library, notification, and interface settings.
- Added an artwork-colored Metal background in Cadence Mode with smooth track-color transitions and activity-aware tinting for keyboard effects.

### Changed

- Adopted QenTerra repository standard 1.3.0 with maintained governance, collaboration, Wiki-source, and repository-health documentation.
- Standardised the README Contact block across the QenTerra repository family.
- Updated GRDB to 7.11.1 and AppAuth to 3.0.0, with canonical XcodeGen dependency pins.

### Fixed

- Improved track-row playback indicators, allowed tracks to appear in both Favorites and Recently Played, and applied inactive-line blur to lyrics instead of track titles.
- Kept automatic library maintenance out of preview sessions so retention settings cannot erase fixture history or interrupt previews with library alerts.

### Removed

- Removed obsolete external donation configuration.

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

[Unreleased]: https://github.com/QenTerra/cadence/compare/v0.2.0-beta.1...HEAD
[0.2.0-beta.1]: https://github.com/QenTerra/cadence/releases/tag/v0.2.0-beta.1
[0.1.0]: https://github.com/QenTerra/cadence/tree/main
