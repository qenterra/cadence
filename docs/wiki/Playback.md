# Playback

Cadence keeps one playback state for the player bar, Now Playing, queue, media
keys, and Control Center. Starting playback from an album, artist, playlist,
smart collection, Favorites, All Tracks, or a set of external files replaces
that state with a queue from the selected source.

## Controls

Cadence provides:

- play, pause, and play/pause toggle;
- seeking to a position or skipping backward and forward;
- previous and next track;
- volume adjustment;
- shuffle for upcoming tracks; and
- repeat off, repeat all, and repeat one.

Play, pause, play/pause, position changes, previous, next, and the configured
skip interval are also registered with macOS media keys and Control Center.

Space toggles playback when focus is not inside a text field, menu, sheet, or
local control. The Lyrics Editor and Import Review own Space for their own
actions, so the global playback shortcut is disabled throughout those views.
Command-Left and Command-Right move between tracks; Command-Up and Command-Down
use the configured volume step.

The previous button either restarts the current track after three seconds or
always moves to the previous track, according to the Playback setting. Manual
next and previous actions wrap around the queue. Automatic advancement stops at
the end unless repeat all is enabled.

## Queue

The queue separates playback history, the current track, and **Up Next**.
Shuffle changes only Up Next; it does not rewrite history or change the current
track. You can play an upcoming item immediately, reorder or remove upcoming
items, clear Up Next, place library tracks next, or append them to the end. Now
Playing displays the current item and up to five upcoming items.

When **Restore Queue** is enabled, Cadence saves the queue, current item,
position, shuffle state, and repeat mode. A restored queue opens paused.
External-file queues are temporary and are not restored after relaunch.

## Audio paths

Cadence selects one of two paths for each track and output route:

- **PCM** uses `AVAudioEngine` for supported mono or stereo AIFF, ALAC, FLAC,
  LPCM, PCM, and WAV audio.
- **Native** uses `AVPlayer` for AirPlay, multichannel or Dolby Atmos audio, and
  compatible files that do not qualify for the PCM path.

Now Playing can show the source codec, container, bit depth, sample rate,
channel count, spatial format, selected backend, renderer format, and output
route. Cadence reports the source and route capabilities; it does not describe
spatialized stereo as a native Dolby Atmos mix.

Route changes re-evaluate the path. If an output disappears, Cadence can resume
after the route recovers when **Resume After Output Reconnects** is enabled.
The player bar includes the system route picker for AirPlay-capable outputs.

Cadence publishes the current title, artist, album, duration, position, playback
state, queue position, and available artwork to the system Now Playing session.

## Normalization and transitions

Volume normalization is either off or **Track ReplayGain**. Cadence applies a
track gain only when the file provides it and limits the gain by the recorded
peak when available.

Crossfade is off by default and can be set to 2, 4, 6, 8, or 12 seconds. It
applies only during normal advancement to a compatible next track on the same
backend. Repeat one, manual skips, missing successors, and backend changes do
not crossfade.

With crossfade off, the PCM path can prepare the next track for a gapless
transition when both tracks use PCM and have matching sample rates and channel
counts. “Gapless” here means Cadence does not insert artificial silence; it is
not a claim that every file, format, or output route will transition without a
device- or decoder-level pause.

## Playback settings

Playback settings provide:

- elapsed or remaining time;
- queue restoration;
- previous-button behavior;
- 5, 10, 15, or 30 second seek steps;
- 2, 5, or 10 percent volume steps;
- Track ReplayGain normalization;
- crossfade duration;
- resume after output reconnection;
- display-sleep prevention while playing;
- lyric text size; and
- technical audio information in Now Playing.

## Cadence Mode

Cadence Mode is an optional Now Playing presentation, not a separate playback
backend or audio effect. Enter it with the **Z + X — Cadence Mode** button or by
pressing Z and X within 180 milliseconds. It can react visually to bass and can
show synchronized lyrics and track information. By default it closes after ten
seconds without input; **Stay in Cadence Mode** disables that timeout.

## External files

Opening registered AAC, AIFF, FLAC, M4A, MP3, or WAV files from Finder creates
an ordered temporary queue containing only the files that were opened. Cadence
does not scan neighboring files or write those tracks to the managed library.
**Add to Library…** sends only the selected external file through the normal
import and duplicate-review flow.

See [Lyrics and LRC](Lyrics-And-LRC), [Library and Import](Library-And-Import),
and [Troubleshooting](Troubleshooting).
