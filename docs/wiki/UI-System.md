# UI System

Cadence uses Soft Graphite surfaces, system typography, monochrome controls,
artwork, and native macOS interaction patterns. Reusable presentation comes
from QenTerraDesignTokens, QenTerraComponents, and QenTerraMediaComponents;
Cadence retains library data, playback actions, and application coordination.

## Shell and workspaces

The navigation rail keeps icon anchors stable as it expands. The central
workspace fills the available area above the full-width player. Tags, Smart
Collections, and Playlists share a resizable two-pane layout while keeping
their own browsing, editing, and playback behavior.

Home presents favorite tracks, albums, and artists separately, followed by
Recently Played. Settings groups playback, library, interface, and app controls.
About resource links use a quiet surface with hover feedback.

## Track tables

Track titles and artists share the leading content column. Album, Year, and
Time are visible by default and can be configured. Headers align with their
row values, and the options button occupies a consistent trailing slot.
Selection uses a background fill without the previous white row outline and
does not change row geometry. The current queue track no longer has a waveform
decoration beside its duration.

## Appearance and motion

System follows macOS appearance; Light and Dark provide explicit choices.
Cadence Mode uses artwork colors for its animated background and keyboard
effects. Timed lyrics retain a clear active line, and Reduce Motion reduces
spatial effects. Missing artwork or lyrics produces a defined fallback.

## Accessibility and verification

Native table keyboard selection, labeled controls, and visible playback states
support navigation. Automated tests and synthetic screenshots exercise layout
and state; they do not replace VoiceOver, target-hardware audio, or frame-pacing
acceptance.

See the canonical [UI guide](https://github.com/QenTerra/cadence/blob/main/docs/UI_SYSTEM.md),
[testing guide](https://github.com/QenTerra/cadence/blob/main/docs/TESTING.md), and
[Playback](Playback).
