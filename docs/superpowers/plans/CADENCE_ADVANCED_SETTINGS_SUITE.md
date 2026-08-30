# Cadence Advanced Settings Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship eleven production settings whose controls, persistence, runtime behavior, and reset/export semantics are complete and verified.

**Architecture:** Extend the typed preference registry, keep all track-table geometry in the shared AppKit table engine, add small runtime policy controllers for startup/notifications/display sleep/maintenance, and wrap each production renderer with a dual-renderer crossfade backend without moving queue ownership out of `PlaybackCoordinator`.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFoundation, SwiftData, UserNotifications, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/CADENCE_ADVANCED_SETTINGS_SUITE_DESIGN.md`

## Global constraints

- Preserve the already-published baseline commit and unrelated user changes.
- Add failing focused tests before production changes for each behavior slice.
- Keep defaults backward-compatible and every portable setting descriptor validated.
- Treat automatic Trash cleanup as destructive and limit it to completed, expired operations.
- Do not claim audible crossfade, Notification Center presentation, or display-sleep behavior from automated tests alone.

---

### Task 1: Typed settings contract and normalized Settings UI

**Files:** `Sources/Cadence/App/CadencePreferences.swift`, `Sources/Cadence/Features/Settings/ProductionSettingsView.swift`, `Sources/Cadence/Features/Settings/SettingsPlaybackView.swift`, new library settings card, `Tests/CadenceTests/CadencePreferencesTests.swift`.

1. Add tests for all defaults, invalid-value repair, portable profile inclusion, runtime destination exclusion, and table-only reset.
2. Run the focused preference tests and confirm the new expectations fail.
3. Add the enums, keys, accessors, descriptors, and `TrackTablePreferences.reset`.
4. Reorganize General, Playback, and Library into native labelled rows and add the eleven controls plus warning/help copy.
5. Rerun focused preference and settings presentation tests.

### Task 2: Global text, table density, and startup navigation

**Files:** `Sources/Cadence/CadenceApp.swift`, `Sources/Cadence/Features/Shell/CadenceRootView.swift`, shared track-table files, startup policy file, geometry tests.

1. Add failing tests for semantic text-size mapping, density geometry, and startup destination repair.
2. Apply Dynamic Type size to both scenes and native fonts to reusable track cells.
3. Thread one density value through `ProductionTrackList`, `ProductionTrackTable`, `TrackTableCore`, and `NativeTrackTableCell`; update row/header/artwork geometry atomically.
4. Persist eligible last-opened destinations and apply the configured startup route once before initial content presentation.
5. Run focused layout/startup tests and AppKit reuse tests.

### Task 3: Notification banners, volume step, and technical metadata

**Files:** notification controller, command router, Now Playing panels, corresponding tests.

1. Add failing tests for per-message foreground presentation, 2/5/10% command deltas, and technical badge suppression.
2. Store foreground presentation intent in notification content and resolve it in the nonisolated delegate.
3. Route command volume deltas through `VolumeAdjustmentStep`.
4. Hide only technical audio metadata when disabled while preserving lyric status.
5. Run notification, command-router, and Now Playing tests.

### Task 4: Crossfade rendering

**Files:** playback backend protocol, new `CrossfadePlaybackBackend.swift`, PCM/native backends, coordinator loading/preferences/audio-path files, playback test support and crossfade tests.

1. Add failing state-machine tests for off passthrough, successor preload, clamped overlap, one queue adoption, pause/seek/stop cancellation, and failed-preload fallback.
2. Add transition preparation and configurable fade-in protocol hooks while keeping default backend compatibility.
3. Implement the generation-safe dual-renderer wrapper and expose AirPlay from the active native child.
4. Instantiate wrapped PCM and native renderers in production and refresh preparation when preferences change.
5. Run all playback coordinator, PCM backend, native backend, routing, and volume tests.

### Task 5: Retention, Trash cleanup, and display sleep

**Files:** repository/store lifecycle and Trash extensions, app-model startup/settings hooks, new display-sleep controller, Settings UI, persistence and controller tests.

1. Add failing repository tests for exact retention cutoffs and completed-only targeted Trash deletion.
2. Add `pruneListeningHistory` and `emptyExpiredTrash`, reusing existing transactional cleanup behavior.
3. Run maintenance after recovery/startup and when settings change; publish refreshed store snapshots and actionable errors.
4. Add a process-activity client and controller whose state follows `isPlaying && preferenceEnabled`.
5. Run focused persistence, lifecycle, recovery, and display-sleep tests.

### Task 6: Localization, screenshots, adversarial review, and release gate

**Files:** string catalog, screenshot baselines only when intentionally changed, Noetic evidence records.

1. Regenerate project metadata and run formatter/linter-compatible checks.
2. Run the full `scripts/verify.sh` gate with the configured Xcode and image Python runtime.
3. Inspect every changed settings screenshot rather than accepting baseline churn blindly.
4. Execute a hostile self-review against destructive scope, stale async generations, queue double-advance, preference import/reset, and route transitions; record that it is not independent because delegation is disabled.
5. Checkpoint and close the Noetic workstream with traceability and manual-acceptance boundaries, then present branch integration options without pushing the feature branch unless authorized.
