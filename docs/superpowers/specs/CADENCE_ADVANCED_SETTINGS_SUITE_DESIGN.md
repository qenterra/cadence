# Cadence Advanced Settings Suite Design

## Objective

Add eleven durable, exportable customization controls and make every control affect the production application immediately or at the next semantically safe boundary. The settings UI stays native to macOS: labelled rows, trailing controls, short explanatory copy, destructive actions called out explicitly, and no decorative container proliferation.

## Product decisions

### Interface

- **Text Size:** Small, Standard, or Large. The main window and Settings window apply a semantic Dynamic Type range; the AppKit track table maps the same preference to native control and metadata fonts.
- **Track Table Density:** Compact, Standard, or Comfortable. The common `ProductionTrackList`/`TrackTableCore` engine owns row height, header height, artwork size, and vertical text geometry, so the setting applies to every track list.
- **Startup Page:** Home, Last Opened, or Tracks. Last Opened persists only a valid primary navigation destination; transient import, trash, search, and detail state are not restored.
- **Reset Track Table View:** restores standard density, artwork visibility, default columns, and Song ascending sort. It does not alter library data or the global text size.

### Playback and Now Playing

- **Volume Step:** 2%, 5%, or 10%; applies to app commands and shortcuts.
- **Crossfade:** Off, 2, 4, 6, 8, or 12 seconds. It overlaps compatible consecutive tracks on both PCM and native playback backends. Manual Next/Previous retains the short transition already used by Cadence. Repeat One does not crossfade into itself. Short tracks clamp the overlap to half of each track.
- **Technical Information:** preserves the synchronized-lyrics status badge but hides codec/sample-rate/bit-depth badges and the audio-details popover when disabled.
- **Keep Display Awake While Playing:** creates a macOS display-sleep activity only while transport is actually playing and releases it on pause, stop, failure, setting disablement, view teardown, and application termination.

### Notifications

- **Show Banners While Cadence Is Active:** controls foreground presentation per notification. Track-change and update notification delivery preferences remain independent. Background notifications continue to use Notification Center policy.

### Library maintenance

- **Recently Played History:** Forever, 30 Days, 90 Days, or 1 Year. Maintenance clears `lastPlayedAt` only for entries older than the selected cutoff; tracks and other metadata remain untouched.
- **Automatic Trash Cleanup:** Never, After 30 Days, After 90 Days, or After 1 Year. Only completed Trash operations older than the cutoff are permanently removed. Fresh and incomplete recovery records are preserved. Cleanup uses the existing transactional permanent-deletion path and surfaces cleanup failures.
- Maintenance runs after library startup/recovery and again when the user changes the retention setting.

## Persistence and profile behavior

All user-facing choices are registered through `CadencePreferences`, validated on read, included in settings export/import, and reset by “Reset All Settings.” The last-opened runtime destination is resettable but excluded from portable exports. Defaults preserve current behavior: Standard text and density, Home startup, foreground banners on, 5% volume step, crossfade off, technical information on, display-sleep prevention off, history forever, and trash cleanup never.

## Playback architecture

`CrossfadePlaybackBackend` wraps two independent renderers of one backend kind. With crossfade off it delegates to the active renderer and preserves PCM gapless scheduling. With crossfade on it preloads the successor in the standby renderer, starts it at zero presentation gain when the remaining time enters the overlap window, ramps both renderers in opposite directions, swaps active ownership, and emits the existing successor-started completion event. The coordinator therefore advances its queue exactly once and continues to own queue semantics.

Crossfade preparation carries the successor normalization gain and current crossfade duration. A generation token makes stale preload and overlap tasks harmless after load, seek, manual navigation, route change, or stop. Failure to preload falls back to the existing non-overlapped completion path rather than interrupting the current track.

## Accessibility and layout

All pickers and switches retain their visible labels and native keyboard behavior. Text scaling uses semantic roles instead of per-view arbitrary point-size multiplication. Compact density never reduces the row below the native hit-target envelope. Reduced Motion disables only visual interpolation; it does not alter audio transition timing.

## Verification boundary

Automated tests cover preference repair/export/reset, common table geometry, startup routing, notification foreground policy, volume step, crossfade state transitions, retention cutoffs, targeted Trash cleanup, and display-sleep activity ownership. The full repository gate covers build, tests, localization, screenshot contracts, and unused code. Audible overlap quality, actual Notification Center banners, and real display sleep remain explicit manual acceptance checks.
