# Lyrics and LRC

Cadence supports plain lyrics and line-level LRC synchronization. It does not
implement word-by-word timing.

## Timing and linking

A synchronized line starts with a timestamp. This example is synthetic:

```text
[01:23.45]The last train fades into the rain
```

During playback, Cadence highlights the active timed line. Selecting a timed
line seeks within the current track; it does not select a different track.

Place audio and LRC files in the same source folder with matching names:

```text
01 - Example Song.flac
01 - Example Song.lrc
```

Cadence proposes matching sidecars during Import Review and copies both files
only after confirmation. Ambiguous matches require review.

## Lyrics Editor

The built-in editor supports editing line text, adding or clearing timestamps,
capturing the current playback time, previewing active-line behavior, and
saving the selected track's managed lyrics. Line order stays explicit; timing
is not invented for untimed text.

## Display

Now Playing and Cadence Mode distinguish the active line from softer inactive
lines. Cadence Mode centers the active line in a compact viewport and shows a
track/status fallback when lyrics are absent or unsynchronized. Reduce Motion
reduces movement while preserving the active-line state.

Plain text can be displayed and edited, but cannot follow playback until it
contains valid timestamps. If synchronization is offset, compare the timestamps
with the actual audio rather than relying on the filename alone.

See [Playback](Playback) and [Library and Import](Library-And-Import).
