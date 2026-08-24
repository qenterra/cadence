# Cadence UI and Motion Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the ten reported UI, animation, list, Settings, and bass behaviors without regressing current-main storage work.

**Architecture:** Keep layout and animation ownership in small pure policies that tests can exercise, while SwiftUI/AppKit bridges apply those policies. Port the bass pipeline selectively from the divergent donor commits, then harden lifecycle and pacing. Optimize the table bridge around stable row identities and bounded invalidation rather than page-wide refreshes.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFAudio, Synchronization, Swift Testing, XCTest screenshot harness.

**Spec:** `docs/superpowers/specs/2026-08-22-cadence-release-recovery-spec.md`

## Global Constraints

- Native macOS 26+, Swift 6, existing dependencies only.
- Do not merge or cherry-pick `qenterra/cadence-mode-bass-polish`; port only reviewed hunks.
- Do not commit, push, tag, sign, publish, authenticate providers, or mutate the real library.
- Honor Reduce Motion and Reduce Transparency.
- Keep screenshot fixtures deterministic and treat live ScreenCaptureKit failure as an explicit verification limit.

---

### Task 1: Navigation and shared row chrome

**Files:**
- Modify: `Sources/Cadence/Components/NavigationRail.swift`
- Modify: `Sources/Cadence/Components/BrowserRowSurface.swift`
- Modify: `Sources/Cadence/Components/FavoriteButton.swift`
- Test: `Tests/CadenceTests/NavigationRailTests.swift`
- Test: `Tests/CadenceTests/AccessibilityContractTests.swift`

**Interfaces:**
- Produces: `NavigationRailMetrics.rowSpacing`, a single value-driven navigation effect, and shared selection chrome without a leading marker.

- [ ] Add failing tests that require nonzero row spacing, no shared leading selection marker, a single navigation animation owner, and Reduce Motion suppression.
- [ ] Run the focused tests and confirm the new expectations fail against current `main`.
- [ ] Change rail buttons to a plain press style, retain one `.bounce.up` value effect, inset visual chrome independently of the hit target, and remove the selected capsule/outline from `BrowserRowSurface`.
- [ ] Make shared optional motion resolve through the Reduce Motion environment and keep favorite actions accessibility-reachable without hover.
- [ ] Run NavigationRail, accessibility, and presentation tests; inspect the focused diff.

### Task 2: Track row and header geometry

**Files:**
- Modify: `Sources/Cadence/Features/Library/ProductionTrackTableRow.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableColumnPolicy.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableLayout.swift`
- Test: `Tests/CadenceTests/TrackTableColumnPolicyTests.swift`

**Interfaces:**
- Produces: `selectionHorizontalInset` and `showsColumnSeparator(isHovered:isDragging:)`.

- [ ] Add failing policy tests asserting a compact horizontal chrome inset and transparent idle resize separators.
- [ ] Run the focused tests and confirm the missing API/behavior fails.
- [ ] Apply the inset to the row background only; preserve full-row content shape and table hit target.
- [ ] Keep the nine-point resize hit target and render the one-point line only on hover/drag.
- [ ] Run focused tests and deterministic All Tracks screenshots.

### Task 3: Boundary-driven lyrics

**Files:**
- Modify: `Sources/Cadence/Features/NowPlaying/ProductionLyricsPanel.swift`
- Modify: `Sources/Cadence/Features/Rhythm/CadenceModeView.swift`
- Modify: `Sources/Cadence/Models/Lyrics.swift`
- Test: `Tests/CadenceTests/LyricsTimelineTests.swift`
- Test: `Tests/CadenceTests/CadenceModeRegressionTests.swift`

**Interfaces:**
- Produces: a lyric observation cadence/next-boundary policy that pauses when playback is not advancing and emits one line-ID change per boundary.

- [ ] Add failing tests for paused cadence, next-boundary scheduling, one transition per ID, and Reduce Motion identity.
- [ ] Prove the current unpaused 120 Hz policy fails those tests.
- [ ] Replace the animation timeline with a bounded periodic or boundary sleep driven by playback state; avoid rebuilding the lyric stack per tick.
- [ ] Use one line emphasis transition and one center scroll per actual ID change; remove blur if it causes offscreen compositing and restore the earlier calm opacity emphasis.
- [ ] Run lyric/Cadence tests plus synchronized lyric screenshots in normal and Reduce Motion fixtures.

### Task 4: Bass-reactive artwork

**Files:**
- Create: `Sources/Cadence/Playback/PCMBassAnalysis.swift`
- Create: `Sources/Cadence/Playback/PlaybackCoordinator+Bass.swift`
- Modify: `Sources/Cadence/Playback/PlaybackBackend.swift`
- Modify: `Sources/Cadence/Playback/PCMPlaybackBackend.swift`
- Modify: `Sources/Cadence/Playback/PCMPlaybackBackend+Scheduling.swift`
- Modify: `Sources/Cadence/Playback/PlaybackCoordinator.swift`
- Modify: `Sources/Cadence/Playback/PlaybackCoordinator+Loading.swift`
- Modify: `Sources/Cadence/Features/Rhythm/CadenceModeView.swift`
- Test: `Tests/CadenceTests/CadenceModeRegressionTests.swift`

**Interfaces:**
- Produces: `PlaybackBassLevelProviding.currentBassLevel() -> Float`, `PlaybackCoordinator.currentBassLevel() -> Float`, adaptive 32–160 Hz PCM analysis, Native envelope fallback, and `CadenceModeBassResponse`.

- [ ] Port donor regression tests first: low-frequency discrimination, quiet/loud normalization, silence/clamping, analyzer reset, detached sendable tap, envelope interpolation, pause/route/track reset, smoothing, Reduce Motion identity.
- [ ] Run the focused tests and confirm compile/behavior failure with no bass pipeline on current source.
- [ ] Port the realtime-safe analyzer and backend/coordinator plumbing from `151946b`, `77d196f`, and `8a0a4bf`, reconciling against current-main playback/storage types instead of replacing files wholesale.
- [ ] Reset every analyzer/envelope generation at load, seek, pause, stop, gapless successor, failure, and backend transition.
- [ ] Drive only bounded artwork scale from a paused-aware display clock; avoid glow/blur layers and main-actor work in the audio callback.
- [ ] Run the focused suite, Swift concurrency build, and actual temporary-WAV integration test. Record audible/bass-feel QA as manual unless directly observed.

### Task 5: Stable native Settings glass

**Files:**
- Modify: `Sources/Cadence/Features/Settings/SettingsTabStrip.swift`
- Modify: `Sources/Cadence/CadenceApp.swift`
- Modify: `Sources/Cadence/DesignSystem/GlassCompatibility.swift`
- Test: `Tests/CadenceTests/SecondAuditPresentationTests.swift`
- Test: `Tests/CadenceTests/SettingsScreenshotTests.swift`

**Interfaces:**
- Produces: one stable tab control subtree and one strip-level native glass/opaque-fallback surface.

- [ ] Add failing tests for identical tab metrics across selection, runtime glass versus screenshot/reduced-transparency fallback, and a single strip surface.
- [ ] Run focused tests and capture current selected/unselected geometry.
- [ ] Give every tab the same button/layout structure; express selection through content/tint/state, not conditional button-style subtrees.
- [ ] Draw glass on the complete top strip in runtime and deterministic opaque material only in approved fallback modes.
- [ ] Run all seven tab screenshots in light/dark/system and compare icon centers.

### Task 6: Proportional track-table updates and artwork decode

**Files:**
- Modify: `Sources/Cadence/Features/Library/ProductionTrackTable.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCore.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoordinator.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoreViews.swift`
- Modify: `Sources/Cadence/Components/ProductionArtworkView.swift`
- Modify: `Sources/Cadence/Components/ArtworkView.swift`
- Test: `Tests/CadenceTests/AllTracksPerformanceTests.swift`

**Interfaces:**
- Produces: a refresh diff that identifies full reload, changed row indexes, and unchanged state; bounded decoded artwork dimensions.

- [ ] Add failing tests proving unchanged updates do zero reloads, selection reloads only old/new rows, stable-identity mutation reloads one row, sorting executes once per semantic input, and track-row decode dimensions stay within the backing-scale budget.
- [ ] Run the focused tests and capture red behavior/counters.
- [ ] Cache sorted projections by input/sort identity, compute an ID/revision diff once, and make `updateNSView` skip selection restoration/viewport requests when inputs are unchanged.
- [ ] Reload only affected rows and update stable hosting content without restarting row-local artwork work.
- [ ] Downsample at decode as a defensive boundary even when the stored variant is already 128 px; retain bounded NSCache cost.
- [ ] Run 1k/10k fixture scroll and mutation performance tests plus the All Tracks million-row window tests.

### Task 7: Native page and accessibility re-audit

**Files:**
- Modify: `Tests/CadenceTests/DocumentationScreenshotTests.swift`
- Modify: `Tests/CadenceTests/CollapsedNavigationScreenshotTests.swift`
- Modify: `Tests/CadenceTests/AccessibilityContractTests.swift`
- Modify: fixture helpers only where coverage is missing.

**Interfaces:**
- Consumes: Tasks 1–6 final UI.
- Produces: a page/scenario coverage manifest and current candidate screenshots without silently accepting unrelated baseline drift.

- [ ] Enumerate every primary destination, transient workspace, nested detail, Settings tab, empty/loading/error state, collapsed rail, appearance, and supported width in a test matrix.
- [ ] Add only missing deterministic fixture renders and accessibility assertions; never bulk-update baselines before reviewing diffs.
- [ ] Diagnose the existing two-pixel-region screenshot failures on macOS 27 separately from product changes and make the harness explicitly OS-stable or version-gated.
- [ ] Run the complete visual suite and inspect every changed candidate.
- [ ] Retry native Computer Use. If ScreenCaptureKit still returns `SCStreamErrorDomain -3811`, record live GUI capture as unavailable and do not claim it passed.

### Task 8: Full UI gate and adversarial review

**Files:**
- Modify only defects found by the independent reviewer.

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: a clean focused/full gate and an explicit manual-acceptance list.

- [ ] Run SwiftFormat lint, SwiftLint, release contract tests, all Swift tests, screenshot tests, and Analyze with the configured Xcode.
- [ ] Run opt-in frame pacing with active temporary PCM analysis, not a paused mock backend.
- [ ] Dispatch a fresh adversarial code/design reviewer with the full uncommitted diff and specification.
- [ ] Fix every Critical/Important finding and rerun the affected and full gates.
- [ ] Verify branch, HEAD base, uncommitted diff, and absence of accidental generated or real-library changes.
