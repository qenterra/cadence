# Privacy

Last updated: July 31, 2026

Cadence is a local macOS music player and library manager. It does not include a
network client, account system, analytics, advertising, telemetry, or crash
reporting service.

## Data Cadence handles

Cadence can read audio, artwork, metadata, and LRC files you select or drop into
the app. After you confirm an import, it copies managed media into:

```text
~/Music/Cadence.library
```

The managed package can contain audio, artwork, lyrics, import manifests,
SwiftData records, and recoverable Trash data. Cadence also stores interface and
playback preferences through macOS preferences.

## Data that stays on your Mac

Cadence does not transmit your library, listening activity, tags, playlists,
artwork, lyrics, search queries, or preferences to QenTerra or another service.
The app opens a URL in your default browser only after you select a GitHub,
Wiki, license, or Buy Me a Coffee link in Settings.

## Files you import

Cadence leaves the selected source files unchanged. Its managed copies remain
under your control. Removing an item from Cadence moves the managed data to the
library's recoverable Trash; emptying that Trash permanently removes those
managed copies.

## macOS permissions

Cadence uses App Sandbox. It requests read access for files and folders you
select and Music folder access for the managed library. macOS controls these
permissions.

## Your choices

You can:

- delete or restore managed items from Cadence Trash;
- empty Cadence Trash;
- remove `~/Music/Cadence.library` after quitting the app to delete the managed
  library;
- reset Cadence preferences through macOS or by removing the app's preference
  data.

Back up music you care about before deleting a library package. Cadence's
managed library is not a substitute for a backup.

## Changes

Any future feature that transmits library data, syncs through a service, or adds
telemetry must update this document before release.

Questions can be opened in the
[Cadence repository](https://github.com/QenTerra/cadence/issues) without
including private media or metadata.
