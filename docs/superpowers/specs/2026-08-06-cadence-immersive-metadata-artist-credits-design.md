# Cadence Immersive Timing, Metadata, and Artist Credits Design

**Date:** 2026-08-06
**Status:** Approved for implementation planning

## Summary

Cadence will replace the coarse Native playback clock with timestamped timeline
samples, preserve the metadata exposed by the source asset, import embedded
lyrics only when an exact sidecar LRC is absent, and represent track artists as
ordered credits. A track remains one managed audio file and one track record
while appearing in every credited artist's track list. Albums remain owned by
their album artist, or by the first track artist when no album-artist tag is
available.

The work must preserve the existing local-first import, managed-library,
recovery, and Trash contracts. It must not mutate source audio or source lyric
files, perform network lookups, or introduce metadata parsing in scrolling UI
paths.

## Goals

- Keep synchronized lyrics aligned in Immersive playback, including startup,
  pause, seek, buffering, and backend transitions.
- Prefer an exact same-folder, same-basename sidecar `.lrc` over every embedded
  lyrics source.
- When no matching sidecar exists, import supported embedded synchronized or
  unsynchronized lyrics into the existing managed lyrics pipeline.
- Capture all metadata values that AVFoundation makes available during import,
  in addition to normalized fields used by Cadence.
- Split track artists using structured multi-value tags and the approved
  conservative textual separators.
- Show one shared track in all credited artist profiles without duplicating its
  managed audio file or library record.
- Preserve album ownership, deletion, restoration, and existing on-disk
  libraries across the schema change.

## Non-goals

- Online metadata or lyrics lookup.
- Editing metadata inside the source audio file.
- Guessing contributors from `&`, `x`, `/`, or `and`.
- Automatically assigning an album to every featured track artist.
- Exposing a full raw-metadata inspector in this change.
- Applying a fixed Immersive lyrics offset. Output-specific magic constants are
  not a reliable clock.

## Alternatives Considered

### Minimal patch

Poll `AVPlayer` more often, split the current artist string, and read a small
set of lyrics tags. This is smaller but leaves stall-aware timekeeping,
migration, Trash, and metadata preservation inconsistent.

### Cohesive domain upgrade (selected)

Introduce backend timeline samples, an ordered artist-credit record, a
versioned source metadata snapshot, and one lyrics-source selection pipeline.
This costs a schema and manifest migration but gives each subsystem one durable
source of truth.

### Lazy parsing in projections

Keep the schema unchanged and decode metadata or split artists whenever a row
or profile is projected. This avoids migration at the expense of repeated work
in the exact data-dense paths that already need to stay cheap.

## Immersive Playback Timeline

### Root cause boundary

Immersive stereo spatialization routes playback from the PCM backend to the
Native `AVPlayer` backend. The Native backend currently polls
`player.currentTime()` every 250 milliseconds, while PCM reports render-derived
time every 100 milliseconds. The coordinator then extrapolates from those
callbacks without knowing whether Native playback is actually advancing or
waiting. This is too coarse and lacks the state required for a trustworthy
lyrics clock.

### Timeline sample

Replace the scalar backend time event with a `PlaybackTimelineSample` carrying:

- media time;
- monotonic host time captured with the sample;
- playback rate or an explicit `isAdvancing` flag.

The coordinator owns a small presentation clock that anchors media time to the
sample's monotonic host time. It extrapolates only while the sample says the
backend is advancing and clamps the result to the current duration.

Native playback uses an `AVPlayer` periodic time observer at approximately
30 Hz and observes `timeControlStatus` so waiting and paused states freeze the
anchor. PCM reports the same sample shape using its render-derived sample time.
Seek, load, finish, failure, and backend-transition commits explicitly re-anchor
the clock.

The lyrics panel continues to render from the coordinator's canonical
presentation time. It does not maintain a second timer or apply a profile-only
offset.

## Source Metadata Capture

### Normalized metadata

`ScannedAudioMetadata` gains normalized fields required by the product:

- original display artist;
- ordered track artist names;
- optional album artist;
- title, album, date/year, track and disc ordering;
- composer, genre, comment, copyright, sort fields, BPM, grouping;
- ReplayGain and known external identifiers when present;
- existing duration, codec, container, sample rate, channels, bitrate, bit
  depth, spatial format, and embedded artwork descriptor.

Known UI and persistence fields remain directly stored and indexed. Raw JSON is
not decoded to build ordinary track rows.

### Raw metadata snapshot

Add a versioned `SourceMetadataSnapshot` containing every metadata item exposed
by AVFoundation across common and container metadata:

- identifier, raw key, key space, locale, and data type;
- textual, numeric, and date values when readable;
- byte count, media type, and content hash for binary values.

Recognized binary payloads needed by the import operation, such as artwork or a
synchronized-lyrics frame, are consumed during inspection. Large binary values
are not duplicated in SwiftData; their descriptors remain in the snapshot and
their managed asset is stored through the existing artwork or lyrics path.

The snapshot is encoded once during inspection, carried by the import manifest,
and stored in `TrackRecord.sourceMetadata`. The snapshot has its own version so
the metadata repair service can identify older normalized-only payloads.

## Embedded Lyrics

### Source precedence

For each audio candidate:

1. Match only a same-folder LRC whose normalized basename exactly matches the
   audio basename.
2. If exactly one sidecar matches, validate and use it.
3. If the sidecar match is absent, inspect embedded lyrics.
4. If sidecar matching is ambiguous or the selected sidecar is malformed,
   preserve the existing visible issue. Do not silently fall back to embedded
   content.

### Supported embedded sources

Inspection recognizes AVFoundation's iTunes Lyrics, ID3 `SYLT` and `USLT`
identifiers and common container keys including `LYRICS`, `SYNCLYRICS`, and
`UNSYNCEDLYRICS`.

- LRC-formatted embedded text is parsed with the existing line-level parser.
- A decodable `SYLT` frame is converted to ordered timed lines.
- Plain `USLT` or lyrics text becomes an unsynchronized lyric document.
- Empty or unreadable embedded values are recorded in the raw snapshot but do
  not create a managed lyric.

The selected embedded document is materialized as
`Lyrics/<track UUID>.lrc` during managed copying. From that point forward,
loading, editing, Trash, recovery, and the synchronized-lyrics pill use the same
managed `LyricRecord` contract regardless of source.

`ManagedImportManifest` advances to version 2 and records the selected lyrics
source plus the metadata snapshot. Recovery accepts version 1 manifests and
upgrades their missing optional fields rather than quarantining otherwise valid
unfinished imports.

## Artist Credits

### Parsing rules

Track credits prefer structured multi-value artist tags. When only a single
display string is available, split on:

- comma;
- semicolon;
- case-insensitive `feat.`, `ft.`, and `featuring` tokens.

Trim whitespace, discard empty components, and deduplicate names using
`SearchNormalizer` while preserving first-seen spelling and order. Do not split
on `&`, `x`, `/`, or `and`.

The original display artist remains stored for track rows and Now Playing. The
first parsed artist is the primary credit; remaining values are contributors.

### Persistence

Cadence schema V4 adds `TrackArtistCreditRecord` with:

- stable UUID and sort identity;
- track relationship;
- artist relationship;
- zero-based position;
- primary or contributor role.

`TrackRecord` remains the single owner of the managed audio path and keeps a
cheap stored display-artist value. Its existing primary artist relationship is
retained as a compatibility and album-fallback field during this migration;
all multi-artist browsing uses credit records.

Artist track counts and artist-detail track queries use distinct credited track
IDs. A shared track therefore appears in both `madkid` and `темный принц`
without a second `TrackRecord`, media file, lyric file, or artwork record.

### Album ownership

An album belongs to the normalized `ALBUMARTIST` when supplied. Otherwise it
belongs to the first track artist. Contributor profiles show the shared track
but not an extra copy of the album. Album identity uses album artist plus album
title, not the combined track display artist.

## Migration and Repair

The V3-to-V4 migration and repair path runs only against managed library data:

1. Decode the existing normalized source metadata when available; otherwise
   use the current artist name.
2. Apply the same approved parser to build ordered credits.
3. Rebind the track's primary artist to the first credit.
4. Keep or assign album ownership to the available album artist, falling back
   to the first credit.
5. Recompute distinct track and album counts.
6. Remove compound artist records only after they have no tracks, albums,
   favorites, or custom artwork requiring preservation.

A resumable, bounded metadata-enrichment pass rescans managed audio whose
snapshot version is old. It fills the complete snapshot, album artist, credits,
and embedded lyrics without network access. It must be idempotent and may not
block initial library rendering.

Migration tests use temporary on-disk V3 fixtures. The real
`~/Music/Cadence.library` is never used as a test target.

## Trash and Restore

Trash manifest version 3 adds track display artist and ordered artist-credit
snapshots. Deleting one credited artist removes only the relationships and
library objects selected by the resolved deletion plan; it does not delete a
shared track still credited to another artist unless the user explicitly chose
that track or its owning album under existing deletion semantics.

Restore recreates all credited artists and ordered relationships before
recomputing counts. Version 2 manifests restore their single `artistID` as one
primary credit, preserving backward compatibility.

## Query and UI Contract

- Library track rows read stored projection fields and do not fetch or decode
  credit collections per row.
- Artist detail resolves tracks through paged credit queries and deduplicates by
  track ID.
- Album pages continue to resolve through album ownership.
- Search matches both the display artist and every credited artist name.
- Queue construction always consumes unique track IDs.
- The synchronized-lyrics pill reflects the final managed lyric timing status,
  independent of whether its source was sidecar or embedded.

## Failure Handling

- A failure to read one optional metadata value does not reject valid audio.
- A malformed embedded lyrics value is retained in the metadata snapshot and
  reported as unavailable or malformed without aborting the audio import.
- Import manifests remain the crash-recovery boundary for audio, artwork,
  lyrics, metadata, and credit insertion.
- Migration and enrichment are idempotent and checkpointed; interruption does
  not create duplicate credits.
- Backend timeline observation is removed on stop and item replacement to avoid
  stale samples reaching a new track.

## Verification

Automated coverage must include:

- presentation-clock extrapolation from timestamped samples;
- Native wait, pause, seek, item replacement, and stale-observer behavior;
- PCM and Native agreement on the timeline sample contract;
- sidecar LRC precedence over embedded lyrics;
- no-sidecar fallback to embedded LRC, `SYLT`, and `USLT`;
- malformed and ambiguous sidecar behavior;
- raw metadata snapshot encoding and version recognition;
- structured and textual multi-artist parsing, deduplication, and the approved
  non-separators;
- one shared track projected in multiple artist profiles with a unique queue ID;
- album-artist ownership and fallback;
- artist, album, and track deletion plus Trash v2/v3 restoration;
- a temporary on-disk V3-to-V4 migration fixture;
- manifest v1-to-v2 recovery compatibility;
- metadata-enrichment cancellation, resume, and idempotency.

The delivery gate is focused red-green testing, `bash scripts/verify.sh`, and a
universal unsigned Release build. Real-device or real-output verification must
cover Immersive playback, Spatial Audio enabled and disabled, seeking,
pause/resume, output-route changes, and representative files carrying embedded
lyrics and multiple artists. These manual checks must be reported separately
from automated results.
