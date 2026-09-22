# Getting Started

Cadence 1.0.2 is the current public release. It runs on Apple silicon
Macs with macOS 26 or later.
Intel and universal binaries are not included.

## Install

1. Download [Cadence-1.0.2-arm64.dmg](https://github.com/QenTerra/cadence/releases/download/v1.0.2/Cadence-1.0.2-arm64.dmg)
   from the [official release](https://github.com/QenTerra/cadence/releases/tag/v1.0.2).
   Compare its SHA-256 with the attached `Cadence-1.0.2-SHA256SUMS.txt`.
2. Open the DMG, drag Cadence to **Applications**, and launch it from there.
3. The app is ad-hoc signed, not Developer ID signed, and **not notarized**.
   If Gatekeeper blocks the first launch and you trust the download, use
   **Open Anyway** for Cadence in **System Settings > Privacy & Security**.
   See [Apple's instructions](https://support.apple.com/en-gb/102445).

Install this release from the DMG or ZIP on the release page.

## Add music

Choose the managed Cadence folder on this Mac or a connected local drive.
Import audio files or folders, review duplicates, and confirm the copy. Cadence
keeps the original files untouched and stores its managed media, artwork, lyrics,
and recoverable Trash together. The catalog remains in sandboxed Application
Support, associated with that folder's library identity.

Opening a supported audio file from Finder creates a temporary playback queue.
Use **Add to Library…** when you want to import the current file.

## Find and organize

Home separates favorite tracks, albums, and artists from Recently Played.
Browse the library by tracks, albums, artists, tags, playlists, or smart
collections. Hierarchical tags and smart-collection rules organize the catalog
without rewriting your source audio files.

Now Playing combines playback, queue, artwork, and line-timed lyrics. Select a
timed lyric line to seek; use the Lyrics Editor to adjust text and timestamps.
Cadence Mode adds an artwork-colored background and keyboard effects.

## Next

- [Architecture](Architecture)
- [Development](Development)
- [Troubleshooting](Troubleshooting)
