# Library and Import

Cadence stores managed media in a local folder and keeps the associated
SwiftData catalog in sandboxed Application Support on this Mac. Its lyrics
search index is derived from the catalog. The managed folder's stable library
identity connects these separate stores.

## Add music

Select audio files or a folder, or drag files and folders from Finder. Each
entry point uses the same flow:

```text
Scan -> Review -> Import -> Complete
```

Scan and Review do not copy files into the managed library. Confirm the review
to import the selected music. Opening audio from Finder for playback is a
temporary queue; choose **Add to Library…** to import it.

## Managed files

The default managed location is `~/Music/Cadence`; you can select another
supported local folder or connected drive. Its media, lyrics, artwork,
metadata, staging, and Trash directories use stable identifiers rather than
track titles as stored filenames. The catalog remains in Application Support,
not inside that folder.

A confirmed import stages files, verifies content hashes, records a versioned
manifest, and commits catalog changes. Recovery handles interrupted imports.
Managed paths must remain inside the selected library folder.

## Duplicates and sidecars

Exact content-hash duplicates are excluded automatically. Possible duplicates
based on metadata remain in Review for your decision. Cadence proposes an LRC
link when the audio and sidecar share a normalized basename in the same folder;
ambiguous matches require review. Linked sidecars are copied with their track.

Import reads embedded title, artist, album, year, duration, format, and artwork
when available. Custom track artwork takes precedence over album artwork; a
placeholder appears when neither is available. Artists, albums, and tracks can
receive user-selected artwork without changing original source files.

## Trash and backup

Removing managed items moves their data into Cadence Trash. **Restore** uses
the saved catalog relationships and files; conflicting destinations are
reported rather than overwritten. **Empty Trash** permanently removes managed
copies and leaves the original source files alone.

Back up both the managed Cadence folder and the app's Application Support data
before an upgrade or library move. Copying the media folder alone is not a
complete catalog backup. **Delete Entire Library** removes both the managed
folder and its local catalog; use it only when you intend to discard that data.

See [Lyrics and LRC](Lyrics-And-LRC), [Tags and Collections](Tags-And-Collections),
and [Privacy and Security](Privacy-And-Security).
