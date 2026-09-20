# Privacy

Last updated: September 20, 2026

Cadence is a local macOS music player and library manager. It does not include
an account system, analytics, advertising, telemetry, or crash-reporting
service.

## Data Cadence handles

Cadence can read audio, artwork, metadata, and LRC files you select or drop into
the app. After you confirm an import, it copies managed media into:

```text
~/Music/Cadence
```

The managed folder can contain audio, artwork, lyrics, import manifests, a
stable library identity, and recoverable Trash data. The SwiftData catalog and
derived lyrics-search index stay in Cadence's sandboxed Application Support
directory on this Mac. Cadence also stores interface and playback preferences
through macOS preferences.

## Data not sent to QenTerra

Cadence does not transmit your managed library or listening data to Nikita
Melnychenko (QenTerra), iCloud, or an analytics service.
The app opens a URL in your default browser only after you select a GitHub,
Wiki, or license link in Settings.
When automatic update checks are enabled, Sparkle reads the public Cadence
update feed and downloads an update only when the configured update policy
allows it.

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
- use **Delete Entire Library** to remove both the managed folder and its local
  Application Support catalog;
- reset Cadence preferences through macOS or by removing the app's preference
  data; and
- disable automatic update checks or automatic downloads in Settings.

Back up music you care about before deleting the library folder. Cadence's
managed library is not a substitute for a backup.

## Changes

Any future account system, library synchronization behavior, or telemetry must
update this document before release.

Questions can be opened in the
[Cadence repository](https://github.com/QenTerra/cadence/issues) without
including private media or metadata.
