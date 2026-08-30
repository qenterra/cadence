# Cadence Unified Library Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved shared track-list, input, appearance, settings, adaptive layout, and semantic-action repairs for every submitted Cadence regression.

**Architecture:** Keep `NSTableView` and `NativeTrackTableCell` as the production list engine, expose one feature-facing `ProductionTrackList` with explicit source and scroll ownership, and move global behavior to window/application policies. Pure layout and decision types provide focused regression seams while AppKit tests verify the real controls and event routing.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Core Animation, Observation, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/CADENCE_UNIFIED_LIBRARY_INTERFACE_DESIGN.md`

## Global Constraints

- Target macOS 26.0 with Swift 6 strict concurrency and add no dependency.
- Work in the user-approved current `main` checkout; do not commit, push, merge, release, sign, or notarize.
- Preserve fixed track columns, paging, selection, queue, drag/drop, artwork caching, and user library state.
- Follow RED → GREEN → REFACTOR for every production behavior.
- Do not mutate a real user library during verification.
- Keep visual/manual acceptance distinct from automated gates.

---

## File Map

- `Sources/Cadence/Features/Library/ProductionTrackList.swift`: sole feature-facing materialized/virtual list surface and scroll ownership.
- `Sources/Cadence/Features/Library/ProductionTrackTable.swift`: forwards scroll ownership into the native core.
- `Sources/Cadence/Features/Library/TrackTableCore.swift`: configures contained versus page-owned native scrolling.
- `Sources/Cadence/Features/Library/NativeTrackTablePresentation.swift`: centered row geometry and embedded-height policy.
- `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`: common text controls, hover continuity, and playback indicator integration.
- `Sources/Cadence/Features/Library/NativePlaybackIndicatorView.swift`: three-bar Core Animation indicator.
- `Sources/Cadence/Features/Library/TrackTableCoordinator.swift`: pointer reconciliation through live scroll.
- Track-list feature call sites: replace direct `ProductionTrackTable` and `NativeAllTracksTable` usage with `ProductionTrackList`.
- `Sources/Cadence/App/AppPlaybackKeyboardCapture.swift`: window-scoped Space decision and event monitor.
- `Sources/Cadence/Features/Shell/CadenceRootView.swift`: hosts playback capture and removes fragile root key handling/appearance identity.
- `Sources/Cadence/App/AppearanceController.swift` and `Sources/Cadence/CadenceApp.swift`: application-only appearance propagation.
- `Sources/Cadence/Features/Settings/SettingsSwitchRow.swift`: compact trailing switch row.
- `Sources/Cadence/Features/Settings/ProductionSettingsView.swift`: adopts switch rows and removes subtree-wide toggle coercion.
- `Sources/Cadence/Features/Settings/SettingsSidebarCard.swift`: leading checkboxes and movable Home.
- `Sources/Cadence/Models/NavigationRailConfiguration.swift`: preserves and moves Home like other destinations.
- `Sources/Cadence/Features/Settings/SettingsAboutSection.swift`: modern product identity and grouped links.
- `Sources/Cadence/DesignSystem/CadenceLayout.swift`: adaptive catalog columns.
- Catalog tile call sites: remove fixed card widths.
- `Sources/Cadence/Components/PlayerBar.swift`: deterministic adaptive region allocation.
- `Sources/Cadence/Features/Home/ProductionHomeView.swift`: Recently Played ordering.
- `Sources/Cadence/DesignSystem/CadenceActionTone.swift`: semantic action colors.
- Existing focused files under `Tests/CadenceTests`: regression coverage for each boundary.

---

### Task 1: Unify Track-List Entry and Page-Owned Scrolling

**Files:**
- Modify: `Sources/Cadence/Features/Library/ProductionTrackList.swift`
- Modify: `Sources/Cadence/Features/Library/ProductionTrackTable.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCore.swift`
- Modify: `Sources/Cadence/Features/Library/NativeAllTracksTable.swift`
- Modify: track-list feature call sites returned by `rg -l 'ProductionTrackTable|ProductionTrackList' Sources/Cadence/Features`
- Modify: `Sources/Cadence/Features/Artists/ProductionArtistDetailView.swift`
- Test: `Tests/CadenceTests/InterfaceScrollPolicyTests.swift`
- Test: `Tests/CadenceTests/LibraryUXInfrastructureTests.swift`

**Interfaces:**
- Produces: `enum TrackListScrollOwnership { case contained, page }`.
- Produces: `TrackListLayout.contentHeight(rowCount:showsHeader:) -> CGFloat`.
- Produces: materialized and virtual `ProductionTrackList` initializers forwarding the full table configuration.
- Consumes: existing `TrackTableContentVersion`, `LibraryTrackWindow`, and `TrackTableCore`.

- [ ] **Step 1: Add failing scroll-policy tests.**

```swift
@Test("Page-owned track lists expand to every row")
func embeddedTrackListHeight() {
    #expect(TrackListLayout.contentHeight(rowCount: 4, showsHeader: true) == 270)
    #expect(TrackListLayout.contentHeight(rowCount: 0, showsHeader: true) == 38)
}
```

- [ ] **Step 2: Run the focused tests and witness missing `TrackListLayout`/ownership failures.**

Run: `xcodebuild test -project Cadence.xcodeproj -scheme Cadence -only-testing:CadenceTests/InterfaceScrollPolicyTests`

- [ ] **Step 3: Implement the minimal source and scrolling policy.**

```swift
enum TrackListScrollOwnership: Equatable, Sendable {
    case contained
    case page
}

enum TrackListLayout {
    static let rowHeight: CGFloat = 58
    static let headerHeight: CGFloat = 38

    static func contentHeight(rowCount: Int, showsHeader: Bool) -> CGFloat {
        CGFloat(max(rowCount, 0)) * rowHeight
            + (showsHeader ? headerHeight : 0)
    }
}
```

- [ ] **Step 4: Route All Tracks, materialized lists, and artist lists through `ProductionTrackList`; use `.page` for both artist sections and remove capped 386/520-point frames.**
- [ ] **Step 5: Run scroll-policy, track-table, artist, album, playlist, smart-collection, and search focused suites.**
- [ ] **Step 6: Record a Noetic implementation checkpoint; do not commit.**

### Task 2: Center Native Row Text and Preserve Hover During Scroll

**Files:**
- Modify: `Sources/Cadence/Features/Library/NativeTrackTablePresentation.swift`
- Modify: `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoordinator.swift`
- Test: `Tests/CadenceTests/AllTracksPerformanceAppKitTests.swift`
- Test: `Tests/CadenceTests/AllTracksPerformanceLiveScrollTests.swift`

**Interfaces:**
- Produces: `NativeTrackMetadataControl`, an `NSTextField`-based accessible clickable label.
- Produces: centered `NativeTrackRowGeometry.singleLineFrame` independent of `titleFrame`.
- Consumes: `NativeTrackTableCell.reconcilePointerHover(at:)` on every visible bounds change.

- [ ] **Step 1: Replace the old title-baseline expectations with failing centered-frame and real-control tests.**

```swift
@Test("Single-line columns occupy the row center")
func metadataColumnsAreCentered() {
    let geometry = NativeTrackRowGeometry(rowHeight: 58)
    #expect(abs(geometry.singleLineFrame.midY - 29) < 0.5)
    #expect(geometry.singleLineFrame.midY != geometry.titleFrame.midY)
}
```

- [ ] **Step 2: Add a failing live-scroll test proving an already-hovered visible cell remains highlighted and reconciliation moves hover to the new cell under a stationary pointer.**
- [ ] **Step 3: Run both focused suites and verify the failures are the old geometry/reset behavior.**
- [ ] **Step 4: Implement the text-field metadata control, compact centered two-line geometry, centered single-line geometry, and live-scroll reconciliation.**
- [ ] **Step 5: Run AppKit, live-scroll, reuse, selection, column, and accessibility suites.**
- [ ] **Step 6: Record a Noetic implementation checkpoint; do not commit.**

### Task 3: Add the Animated Native Playback Indicator

**Files:**
- Create: `Sources/Cadence/Features/Library/NativePlaybackIndicatorView.swift`
- Modify: `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`
- Test: `Tests/CadenceTests/AllTracksPerformanceAppKitTests.swift`
- Modify: `Cadence.xcodeproj/project.pbxproj` through XcodeGen.

**Interfaces:**
- Produces: `NativePlaybackIndicatorView.setPlaying(_:reduceMotion:)`.
- Produces: `isAnimating` and `barCount` read-only test seams.
- Consumes: `TrackRowDisplayProjection.isCurrentTrack`, `.isPlaying`, cell reuse, and Reduce Motion.

- [ ] **Step 1: Add failing real-view tests for three bars, playing animation, paused hiding, and static Reduce Motion.**

```swift
let indicator = NativePlaybackIndicatorView(frame: .init(x: 0, y: 0, width: 40, height: 40))
indicator.setPlaying(true, reduceMotion: false)
#expect(indicator.barCount == 3)
#expect(indicator.isAnimating)
indicator.setPlaying(true, reduceMotion: true)
#expect(!indicator.isAnimating)
```

- [ ] **Step 2: Run the focused AppKit test and witness the missing type failure.**
- [ ] **Step 3: Implement three mouse-transparent rounded bar layers with staggered repeating keyframes and deterministic teardown.**
- [ ] **Step 4: Integrate it into the stable native-cell hierarchy; hide the waveform symbol for the active playing row and preserve the play symbol for hover/paused state.**
- [ ] **Step 5: Regenerate with `xcodegen generate`, then run AppKit/reuse/performance suites and ensure cell hierarchy remains stable.**
- [ ] **Step 6: Record a Noetic implementation checkpoint; do not commit.**

### Task 4: Make Space and Appearance Window-Correct

**Files:**
- Create: `Sources/Cadence/App/AppPlaybackKeyboardCapture.swift`
- Modify: `Sources/Cadence/Features/Shell/CadenceRootView.swift`
- Modify: `Sources/Cadence/App/AppearanceController.swift`
- Modify: `Sources/Cadence/CadenceApp.swift`
- Test: `Tests/CadenceTests/AppCommandRouterTests.swift`
- Test: `Tests/CadenceTests/AppearanceControllerTests.swift`
- Test: `Tests/CadenceTests/LibraryUXInfrastructureTests.swift`

**Interfaces:**
- Produces: `AppPlaybackKeyDecision.focus(firstResponder:isMenuOpen:hasSheet:hasModal:)`.
- Produces: `AppPlaybackKeyDecision.handlesSpace(keyCode:isRepeat:modifierFlags:focus:) -> Bool`.
- Produces: `AppPlaybackKeyboardCapture(onToggle:)` that consumes only a handled command.
- Changes: `AppearanceController.apply` sets `application.appearance` only.

- [ ] **Step 1: Add failing key-decision tests for ordinary Space, text editing, local controls, modifiers, repeats, menus, sheets, and unrelated keys.**
- [ ] **Step 2: Add a failing AppKit lifecycle test that sends key code 49 to a hosted root with a non-editable first responder and observes one playback toggle.**
- [ ] **Step 3: Replace appearance tests with a failing contract that an explicit window override survives controller application while the application override changes and System becomes `nil`.**
- [ ] **Step 4: Run focused command/appearance tests and verify the old root-only key path and per-window override behavior fail.**
- [ ] **Step 5: Implement the capture, remove root `.onKeyPress(.space)`, remove appearance-derived `.id` values, and simplify `AppearanceController`.**
- [ ] **Step 6: Run command, Rhythm capture, import review, lyrics sync, appearance, and root lifecycle suites.**
- [ ] **Step 7: Record a Noetic implementation checkpoint; do not commit.**

### Task 5: Modernize Settings, Navigation, About, and Action Semantics

**Files:**
- Create: `Sources/Cadence/Features/Settings/SettingsSwitchRow.swift`
- Create: `Sources/Cadence/DesignSystem/CadenceActionTone.swift`
- Modify: `Sources/Cadence/Features/Settings/ProductionSettingsView.swift`
- Modify: `Sources/Cadence/Features/Settings/SettingsSidebarCard.swift`
- Modify: `Sources/Cadence/Features/Settings/SettingsAboutSection.swift`
- Modify: `Sources/Cadence/Models/NavigationRailConfiguration.swift`
- Modify: confirmation/destructive button call sites in Settings, import, library, playlists, smart collections, lyrics, and artwork features.
- Test: `Tests/CadenceTests/NavigationRailTests.swift`
- Test: `Tests/CadenceTests/LibraryUXInfrastructureTests.swift`
- Test: `Tests/CadenceTests/SemanticLayoutTests.swift`

**Interfaces:**
- Produces: `SettingsSwitchRow<Label>` with trailing `.small` switch.
- Produces: `SettingsAboutMetadata(version:build:)` bundle resolver.
- Produces: `CadenceActionTone.nativeColor` and `.cadenceActionTone(_:)`.
- Changes: `NavigationRailConfiguration.moving` and `orderedDestinations` treat Home uniformly.

- [ ] **Step 1: Add failing navigation tests preserving `favorites,home,...` and moving Home after Favorites without duplicates.**
- [ ] **Step 2: Add failing layout/presentation tests for compact switch control size, leading checkbox policy, About version/build fallback, and blue/red semantic tone resolution.**
- [ ] **Step 3: Run the focused settings/navigation tests and witness failures against the old Home and switch policies.**
- [ ] **Step 4: Implement `SettingsSwitchRow`, remove subtree-wide `.toggleStyle(.switch)`, and convert Cadence Mode/update Boolean rows.**
- [ ] **Step 5: Make navigation rows use a leading checkbox and remove every Home drag/move guard.**
- [ ] **Step 6: Replace the About tile grid with the approved product identity and grouped link list.**
- [ ] **Step 7: Add semantic tones while retaining destructive/cancel roles, labels, symbols, and disabled states.**
- [ ] **Step 8: Regenerate the project and run navigation, settings, accessibility, action, and screenshot-content suites.**
- [ ] **Step 9: Record a Noetic implementation checkpoint; do not commit.**

### Task 6: Fill Catalog Width, Expand Player Metadata, and Reorder Home

**Files:**
- Modify: `Sources/Cadence/DesignSystem/CadenceLayout.swift`
- Modify: all catalog tiles returned by `rg -l 'CatalogCardLayoutMetrics.cardWidth' Sources/Cadence`
- Modify: `Sources/Cadence/Components/PlayerBar.swift`
- Modify: `Sources/Cadence/Features/Home/ProductionHomeView.swift`
- Test: `Tests/CadenceTests/SemanticLayoutTests.swift`
- Test: `Tests/CadenceTests/NowPlayingLayoutTests.swift`
- Test: `Tests/CadenceTests/LibraryUXInfrastructureTests.swift`

**Interfaces:**
- Produces: adaptive `CatalogCardLayoutMetrics.layoutColumns(spacing:)` with minimum 196 and unbounded fill.
- Produces: `PlayerBarRegionLayout(availableWidth:)` with `metadataWidth`, `transportWidth`, and `outputWidth`.
- Produces: `HomeSectionOrder.default == [.recentlyPlayed, .pinned, .favorites]` for a pure ordering seam.

- [ ] **Step 1: Replace the fixed-card test with a failing adaptive-column contract and add literal player allocations for 1080, 1512, and 1920-point windows.**
- [ ] **Step 2: Add a failing Home order test requiring Recently Played before pins and favorites.**
- [ ] **Step 3: Run focused layout tests and witness fixed width, fixed player region, and old Home ordering failures.**
- [ ] **Step 4: Make grid columns adaptive and every catalog tile fill its offered width.**
- [ ] **Step 5: Implement `PlayerBarRegionLayout`, use exact geometry-driven region frames, and give title/artist higher layout priority than trailing metadata controls.**
- [ ] **Step 6: Move Recently Played directly after the Home header and retain empty-state logic.**
- [ ] **Step 7: Run semantic layout, album, artist, Home, Favorites, Search, and player suites.**
- [ ] **Step 8: Record a Noetic implementation checkpoint; do not commit.**

### Task 7: Cross-Context and Full Verification

**Files:**
- Modify: focused test files only if real integration evidence exposes a missing approved case.
- Create: `docs/verification/CADENCE_UNIFIED_LIBRARY_INTERFACE.md`.

**Interfaces:**
- Consumes: every interface produced by Tasks 1–6.
- Produces: one evidence record separating automated, static, screenshot, and manual results.

- [ ] **Step 1: Run a context matrix for All Tracks, album, artist, playlist, smart collection, favorites, search, tags, and library lists.**
- [ ] **Step 2: Run strict build and all focused suites with one reusable Derived Data directory under `/private/tmp`.**
- [ ] **Step 3: Run `scripts/verify.sh` once focused gates are green.**
- [ ] **Step 4: Inspect `git diff --check`, `git status`, generated project consistency, and the complete diff for unrelated changes or source-only pseudo-tests.**
- [ ] **Step 5: Launch a bounded preview/native app walkthrough for Space, theme frame, toggle alignment, Home drag, list hover while scrolling, animated bars, grid width, player title, Home order, semantic colors, and artist page scrolling.**
- [ ] **Step 6: Write the verification record with explicit unresolved manual acceptance items; never label them accepted automatically.**
- [ ] **Step 7: Run the final Noetic integrity check and close the workstream only if all required work and evidence are complete.**
