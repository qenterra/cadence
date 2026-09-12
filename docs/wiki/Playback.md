# Playback

`PlaybackCoordinator` owns the queue, current item, timing, volume, repeat,
shuffle, and Now Playing state. Views observe that state instead of maintaining
independent clocks.

## Backends

Cadence chooses between two playback paths:

- **PCM** uses `AVAudioEngine` for supported mono or stereo PCM and lossless files.
- **Native** preserves system handling for formats, multichannel material, and
  routes that need it.

The selected route is shown in Now Playing under **Audio Path**, together with
the file format, sample rate, channel count, and output device.

## Routing and preferences

Routing is automatic. AirPlay, multichannel, and Dolby Atmos sources use the
Native backend; supported mono and stereo PCM sources can use AVAudioEngine.
Cadence reports source and route capabilities without treating spatialized
stereo as a native Atmos mix.

Playback settings include queue restoration, previous-button behavior, seek
and volume steps, normalization, crossfade, and reconnect behavior. A restored
queue starts paused. Track ReplayGain is used only when the file supplies it;
crossfade applies to normal advancement between tracks.

## Queue behavior

The queue is canonical across the player bar and Now Playing. You can select a
queued track to play it immediately and reorder upcoming items. Shuffle and
repeat controls display their active state rather than relying on menu state
alone.

## System integration

Media keys, Control Center, app controls, and track navigation feed the same
coordinator. Route changes, including connecting or disconnecting headphones,
reconfigure the active backend without creating a competing playback session.

## Transitions

Cadence uses short ramps for start, pause, and compatible track transitions to
avoid clicks without making controls feel delayed. Gapless-capable transitions
prepare the next compatible item before the current item completes.

Gapless means there is no artificial silence between consecutive files. It is
especially useful for live recordings, DJ mixes, and albums where one track
continues into the next.


See [Lyrics and LRC](Lyrics-And-LRC), [Library and Import](Library-And-Import),
and [Troubleshooting](Troubleshooting).
