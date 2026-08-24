# Cadence Now Playing and Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Make Player Bar navigation, Now Playing metadata, queue windowing,
lyrics motion, and Cadence Mode controls/preferences behave predictably and
leave visual space for effects.

**Architecture:** Keep the full playback queue and expose a five-item
presentation window. Centralize Cadence Mode options in one value consumed by
settings, keyboard capture, direct activation, and layout. Treat lyric initial
position separately from later active-line following.

**Tech Stack:** Swift 6, SwiftUI, AppKit-compatible model state, Swift Testing,
XCTest visual fixtures.

**Spec:** `docs/superpowers/specs/2026-08-24-cadence-interface-coherence-design.md`

## Global Constraints

- Implement CUI-16 through CUI-24 exactly as specified.
- Preserve the complete underlying playback queue and playback coordinator.
- The Back pill and appearance changes must never stop playback.
- Respect Reduce Motion and keep Cadence Mode effects interruptible.
- Follow RED -> GREEN -> REFACTOR and do not commit or push.

---

### Task 1: Player artwork routing and five-item queue window

**Files:**

- Modify: `Tests/CadenceTests/NowPlayingPresentationTests.swift`
- Modify: `Tests/CadenceTests/PlaybackQueueStateTests.swift`
- Modify: `Sources/Cadence/App/CadenceAppModel+NowPlaying.swift`
- Modify: `Sources/Cadence/Components/PlayerBar.swift`
- Modify: `Sources/Cadence/Playback/PlaybackQueueState.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore+PlaybackQueue.swift`

**Interfaces:**

- Produces: `presentNowPlaying(panel: NowPlayingPanel) -> Bool` preserving draft
  transition safety.
- Produces: `PlaybackQueuePresentation.maximumUpNextCount == 5` behavior.

- [x] **Step 1: Add a failing navigation test with no resident lyric document.
  Activate Player Bar artwork and assert workspace `.nowPlaying` and panel
  `.lyrics`, never `.queue`.**
- [x] **Step 2: Add failing queue tests with 20 tracks: presentation returns
  current + five; after moving current by one it returns the next current +
  next five; `orderedTrackIDs` remains all 20.**
- [x] **Step 3: Implement explicit panel presentation through the existing dirty
  lyric-draft transition path and route artwork to `.lyrics`.**
- [x] **Step 4: Set the presentation window to five and verify store fetches at
  most six projections without truncating state.**
- [x] **Step 5: Run Now Playing, queue, persistence, and contextual-navigation
  suites.**

### Task 2: Now Playing format and synchronized-LRC pills

**Files:**

- Create: `Sources/Cadence/Features/NowPlaying/NowPlayingMetadataBadges.swift`
- Create: `Tests/CadenceTests/NowPlayingMetadataBadgesTests.swift`
- Modify: `Sources/Cadence/Features/NowPlaying/ProductionNowPlayingView+Panels.swift`
- Modify: `Sources/Cadence/Features/NowPlaying/ProductionNowPlayingView.swift`

**Interfaces:**

- Produces: `NowPlayingMetadataBadges.resolve(audioPath:lyricDocument:)` with
  format detail and `showsSynchronizedLyrics`.

- [x] **Step 1: Add failing literal tests for missing, static, partial, and
  synchronized lyric documents; only synchronized returns LRC true.**
- [x] **Step 2: Add a failing stale-track test proving an accepted document for
  A cannot badge B.**
- [x] **Step 3: Implement one HStack containing the existing format button and
  conditional LRC capsule. Keep the format popover behavior unchanged.**
- [x] **Step 4: Feed the current accepted Cadence/Now Playing lyric document and
  run metadata, lyric loading, and accessibility tests.**

### Task 3: Cadence Mode options and direct activation

**Files:**

- Modify: `Sources/Cadence/Features/Rhythm/CadenceModePreferences.swift`
- Modify: `Sources/Cadence/Features/Rhythm/CadenceModeState.swift`
- Modify: `Sources/Cadence/Features/Rhythm/CadenceModeInputCapture.swift`
- Modify: `Sources/Cadence/Features/Settings/ProductionSettingsView.swift`
- Modify: `Sources/Cadence/Features/Rhythm/CadenceModeHint.swift`
- Modify: `Sources/Cadence/Features/NowPlaying/ProductionNowPlayingView.swift`
- Modify: `Tests/CadenceTests/CadenceModeStateTests.swift`
- Modify: `Tests/CadenceTests/SettingsPresentationTests.swift`

**Interfaces:**

- Produces: `CadenceModeOptions` with isEnabled, reactsToBass, showsLyrics,
  showsTrackInformation, and staysActive.
- Produces: `CadenceModeSession.requestActivation(canActivate:)` using the same
  pending-presentation state as keyboard activation.

- [x] **Step 1: Add failing defaults/persistence tests for all five options.**
- [x] **Step 2: Add failing direct activation tests: enabled + track requests
  presentation; disabled or no track does nothing; disabling while active
  deactivates and releases keys.**
- [x] **Step 3: Implement stable preference keys/options and expose five toggles
  in the existing Settings card with concise dependent help text.**
- [x] **Step 4: Convert `CadenceModeHint` to a bordered pill Button and route it
  through direct activation. Input capture receives `isEnabled`.**
- [x] **Step 5: Add the active top-left Back pill invoking `deactivate`, keep
  Escape, and run state/input/settings/accessibility tests.**

### Task 4: Cadence Mode layout, content options, bass, and artwork border

**Files:**

- Modify: `Tests/CadenceTests/CadenceModeLayoutTests.swift`
- Modify: `Tests/CadenceTests/CadenceModeRegressionTests.swift`
- Modify: `Sources/Cadence/Features/Rhythm/CadenceModeLayout.swift`
- Modify: `Sources/Cadence/Features/Rhythm/CadenceModeView.swift`
- Modify: `Sources/Cadence/Features/NowPlaying/ProductionNowPlayingView.swift`

**Interfaces:**

- Produces: `CadenceModeLayout(canvasSize:contextWidth:options:)` with a
  maximum 560-point artwork frame and optional identity/lyrics frames.
- Consumes: `CadenceModeOptions` for content and bass response.

- [x] **Step 1: Replace the old large-display expectation with failing literal
  tests asserting artwork `<= 560`, a non-overlapping effects perimeter, and
  valid frames for all lyrics/identity option combinations.**
- [x] **Step 2: Add a failing bass test proving disabled response returns
  identity scale for level 1 while keyboard pulse state remains untouched.**
- [x] **Step 3: Implement the 560 cap and optional layout slots. Show compact
  title/artist only when requested and synchronized lyrics only when requested.**
- [x] **Step 4: Gate the bass Timeline response, and add a 0.5-point
  `white.opacity(...)` rounded border outside the scaled artwork.**
- [x] **Step 5: Run layout, bass, frame-pacing, visual readiness, and regression
  suites.**

### Task 5: Shortcut catalog entry

**Files:**

- Modify: `Tests/CadenceTests/SettingsPresentationTests.swift`
- Modify: `Sources/Cadence/Features/Settings/ShortcutsSettingsView.swift`

**Interfaces:**

- Produces: `ShortcutKey.z`, `ShortcutKey.x`, and catalog entry
  `cadence-mode` with `[.z, .x]`.

- [x] **Step 1: Add a failing catalog test asserting the Cadence Mode entry and
  literal `Z`, `X` glyphs.**
- [x] **Step 2: Implement the key cases and entry, preserving existing keyboard
  reference accessibility.**
- [x] **Step 3: Run Settings and shortcut tests.**

### Task 6: Lyrics initial position and calm follow motion

**Files:**

- Create: `Sources/Cadence/Features/NowPlaying/LyricsScrollPresentation.swift`
- Create: `Tests/CadenceTests/LyricsScrollPresentationTests.swift`
- Modify: `Sources/Cadence/Features/NowPlaying/ProductionLyricsPanel.swift`
- Modify: `Tests/CadenceTests/LyricsTimelineTests.swift`

**Interfaces:**

- Produces: `LyricsScrollPresentation` with initial `.top` and later
  `.activeLine(id, duration: 0.32)` actions.

- [x] **Step 1: Add failing state tests: new track emits one non-animated top
  reset; the initial accepted active line does not override it; the next active
  line emits a 0.32-second follow; Reduce Motion emits an immediate follow.**
- [x] **Step 2: Implement a top sentinel and track-keyed scroll presentation.
  Hide indicators and keep scrolling/line seeking enabled.**
- [x] **Step 3: Apply calm follow motion to scroll and emphasis, ensure edits
  retain local Escape behavior, and run lyric timeline/editor/panel tests.**

### Task 7: Now Playing and Cadence Mode verification checkpoint

**Files:**

- Modify: `docs/verification/2026-08-24-interface-coherence.md`

- [x] Run queue, Now Playing, lyrics, Cadence Mode, Settings, frame-pacing, and
  accessibility focused tests.
- [x] Render temporary minimum/default/wide/fullscreen Now Playing and Cadence
  Mode frames in dark/light/system without promoting baselines.
- [x] Record manual checks for Back, direct activation, Z+X, bass toggle,
  optional lyrics/identity, Player Bar artwork, and continuous playback.
