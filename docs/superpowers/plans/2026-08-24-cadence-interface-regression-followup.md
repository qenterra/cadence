# Cadence Interface Regression Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair every screenshot-backed track-list, catalog, Home, playlist, Smart Collections, Cadence Mode, lyrics-editor, and Settings regression in the approved follow-up spec.

**Architecture:** Keep AppKit track-row state authoritative at the native cell/coordinator boundary, introduce one stable-ID catalog selection policy, and route cross-view mutations such as named playlist creation through `CadenceAppModel`. Presentation-only fixes stay in their owning SwiftUI components, while root loading policy only gates data it owns.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Observation, Swift Testing, XcodeGen, deterministic documentation screenshot infrastructure.

**Spec:** `docs/superpowers/specs/2026-08-24-cadence-interface-regression-followup-design.md`

## Global Constraints

- Target macOS 26.0 and Swift 6 strict concurrency; add no dependency.
- Preserve fixed track-table columns, current queue paging, sidebar ordering, and zero sidebar icon animation.
- Store selection by stable UUID, never by transient row or grid index alone.
- Do not mutate a real user library during verification; use fixtures or preview stores.
- Write each mechanically observable regression first and witness the focused RED failure.
- Keep screenshots in a temporary untracked directory; do not promote baselines merely to make a diff green.
- The active Noetic contract forbids commit, push, merge, release, signing, and notarisation. Checklist commit steps are intentionally replaced by status checkpoints.

---

## File Map

- `Sources/Cadence/Features/Library/NativeTrackTablePresentation.swift`: pure favorite visibility, row geometry, and modifier policies shared by native cells and tests.
- `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`: pointer reconciliation, static favorite rendering, geometry application, and event-aware context menu callback.
- `Sources/Cadence/Features/Library/TrackTableCoordinator.swift`: live-scroll hover reset/reconciliation.
- `Sources/Cadence/Features/Library/TrackTableCoordinator+Actions.swift`: explicit selection modifiers and pre-context-menu selection.
- `Sources/Cadence/Components/FavoriteButton.swift`: optimistic fill/unfill without symbol motion.
- `Sources/Cadence/Models/CatalogSelection.swift`: stable-ID single, additive, range, and activation policy.
- `Sources/Cadence/App/CadenceAppModel.swift`: owns catalog selection and pending named-playlist request.
- `Sources/Cadence/Components/CatalogSortMenu.swift`: direct field and direction menu shared by albums and artists.
- `Sources/Cadence/Features/Albums/ProductionAlbumsView.swift`: modifier-aware album selection and shared sort control.
- `Sources/Cadence/Features/Artists/ProductionArtistsView.swift`: modifier-aware artist selection, shared sort control, and Home pin action.
- `Sources/Cadence/Features/Playlists/PlaylistsView.swift`: modifier-aware playlist selection while preserving primary detail selection.
- `Sources/Cadence/Components/BrowserRowSurface.swift`: static pressed symbol presentation.
- `Sources/Cadence/Features/Home/ProductionHomeSupport.swift`: optional trailing accessory and no track triangle.
- `Sources/Cadence/Features/Home/ProductionHomeView+Sections.swift`: typed pinned shelves.
- `Sources/Cadence/Persistence/LibraryStore+Playlists.swift`: creation returns the created projection.
- `Sources/Cadence/Features/Playlists/AddToPlaylistMenuItems.swift`: requests named creation rather than eagerly creating Untitled Playlist.
- `Sources/Cadence/Features/Shell/CadenceRootView.swift`: named-playlist alert and non-deadlocking Smart Collections presentation.
- `Sources/Cadence/Features/NowPlaying/ProductionNowPlayingView.swift`: bounded track-context scrolling and native Back presentation.
- `Sources/Cadence/Features/LyricsEditor/TapToSyncPanel.swift`: presentation-clock timeline.
- `Sources/Cadence/Features/Settings/ProductionSettingsView.swift`: native macOS switch style.
- `Tests/CadenceTests/AllTracksPerformanceAppKitTests.swift`: native cell and geometry regressions.
- `Tests/CadenceTests/AllTracksPerformanceLiveScrollTests.swift`: hover ownership through live scrolling.
- `Tests/CadenceTests/AllTracksPerformanceSelectionTests.swift`: modifier and context-click selection.
- `Tests/CadenceTests/TrackSelectionControllerTests.swift`: catalog additive/range/activation semantics.
- `Tests/CadenceTests/LibraryUXInfrastructureTests.swift`: Home pin grouping, Smart Collections presentation, playlist request, and settings policies.
- `Tests/CadenceTests/ProductionPlaybackAppModelTests.swift`: lyrics presentation-clock behavior.
- `Tests/CadenceTests/CadenceModeLayoutTests.swift`: short-workspace hint bounds and Back presentation policy.
- `Cadence.xcodeproj/project.pbxproj`: regenerated by XcodeGen after new Swift files are added.

---

### Task 1: Native Favorite and Hover Ownership

**Files:**
- Create: `Sources/Cadence/Features/Library/NativeTrackTablePresentation.swift`
- Modify: `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoordinator.swift`
- Modify: `Sources/Cadence/Components/FavoriteButton.swift`
- Test: `Tests/CadenceTests/AllTracksPerformanceAppKitTests.swift`
- Test: `Tests/CadenceTests/AllTracksPerformanceLiveScrollTests.swift`

**Interfaces:**
- Produces: `NativeFavoriteVisibility.resolve(isFavorite:isHovered:isLiveScrolling:) -> NativeFavoriteVisibility`.
- Produces: `NativeTrackTableCell.resetPointerHover()` and `reconcilePointerHover(windowPoint:)`.
- Consumes: existing `TrackTableInteractionState.isLiveScrolling` and `FavoriteButtonTransientState` request token.

- [x] **Step 1: Add failing favorite visibility and reuse tests.**

```swift
@Test("A non-favorite heart belongs only to the actual hovered row")
func nativeFavoriteVisibilityIsPointerOwned() {
    #expect(NativeFavoriteVisibility.resolve(
        isFavorite: false,
        isHovered: false,
        isLiveScrolling: false
    ) == .hidden)
    #expect(NativeFavoriteVisibility.resolve(
        isFavorite: false,
        isHovered: true,
        isLiveScrolling: false
    ) == .emptySecondary)
    #expect(NativeFavoriteVisibility.resolve(
        isFavorite: false,
        isHovered: true,
        isLiveScrolling: true
    ) == .hidden)
    #expect(NativeFavoriteVisibility.resolve(
        isFavorite: true,
        isHovered: false,
        isLiveScrolling: true
    ) == .filledPrimary)
}

@Test("Selection never reveals an idle non-favorite heart")
func nativeSelectionDoesNotRevealFavoriteControl() throws {
    let cell = NativeTrackTableCell()
    cell.configure(
        .track(nativeInteractionProjection(index: 8)),
        columns: [],
        widths: TrackTableColumnPolicy.defaultWidths,
        isSelected: true,
        isFocused: true,
        isLiveScrolling: false
    )
    #expect(try nativeFavoriteButton(in: cell).isHidden)
}
```

- [x] **Step 2: Run the focused AppKit suite and confirm RED.**

Run:

```bash
DEVELOPER_DIR='/Applications/Developing & Coding/Xcode.app/Contents/Developer' xcodebuild -project Cadence.xcodeproj -scheme Cadence -configuration Debug -derivedDataPath .build/DerivedData -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:CadenceTests/AllTracksPerformanceTests test
```

Expected: compilation fails because `NativeFavoriteVisibility` and the cell reconciliation API do not exist, or the selected non-favorite remains visible.

- [x] **Step 3: Implement the pure favorite presentation and pointer reconciliation.**

```swift
enum NativeFavoriteVisibility: Equatable, Sendable {
    case hidden
    case emptySecondary
    case filledPrimary

    static func resolve(
        isFavorite: Bool,
        isHovered: Bool,
        isLiveScrolling: Bool
    ) -> Self {
        if isFavorite { return .filledPrimary }
        return isHovered && !isLiveScrolling ? .emptySecondary : .hidden
    }
}
```

`NativeTrackTableCell.reconcilePointerHover(windowPoint:)` converts from window coordinates and intersects `bounds`, `visibleRect`, and `window != nil`. `resetPointerHover()` also resets artist and album metadata hover. `updateChrome()` uses only `NativeFavoriteVisibility`; selection and focus are not inputs.

- [x] **Step 4: Reconcile visible native cells at scroll boundaries.**

```swift
private func resetVisiblePointerHover() {
    visibleRowIndexes().forEach { row in
        (tableView?.view(atColumn: 0, row: row, makeIfNecessary: false)
            as? NativeTrackTableCell)?.resetPointerHover()
    }
}

private func reconcileVisiblePointerHover() {
    guard let point = tableView?.window?.mouseLocationOutsideOfEventStream else { return }
    visibleRowIndexes().forEach { row in
        (tableView?.view(atColumn: 0, row: row, makeIfNecessary: false)
            as? NativeTrackTableCell)?.reconcilePointerHover(windowPoint: point)
    }
}
```

Call reset after `beginLiveScroll()` and reconciliation after `endLiveScroll()` and non-live visible-bound changes.

- [x] **Step 5: Remove all favorite motion while preserving optimistic state.**

Delete `NativeFavoriteFeedbackPresentation`, `animateFavoriteFeedback()`, feedback triggers, `.contentTransition(.symbolEffect(.replace))`, and `.symbolEffect(.bounce.up)`. Render a plain `Image(systemName: displayedValue ? "heart.fill" : "heart")`; keep pending value and request token logic.

- [x] **Step 6: Regenerate the Xcode project for the new presentation source.**

```bash
xcodegen generate --spec project.yml
```

- [x] **Step 7: Re-run AppKit and live-scroll suites and confirm GREEN.**

Run the command from Step 2 plus:

```bash
DEVELOPER_DIR='/Applications/Developing & Coding/Xcode.app/Contents/Developer' xcodebuild -project Cadence.xcodeproj -scheme Cadence -configuration Debug -derivedDataPath .build/DerivedData -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:CadenceTests/AllTracksPerformanceTests/trackTableFollowsNativeLiveScrollNotifications test
```

Expected: all selected tests pass and only one non-favorite visible cell may own hover.

- [x] **Step 8: Record checkpoint.**

Run `git status --short` and record Task 1 files; do not commit under the active contract.

---

### Task 2: Track Geometry, Selection Chrome, and Context Modifiers

**Files:**
- Modify: `Sources/Cadence/Features/Library/NativeTrackTablePresentation.swift`
- Modify: `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoordinator+Actions.swift`
- Test: `Tests/CadenceTests/AllTracksPerformanceAppKitTests.swift`
- Test: `Tests/CadenceTests/AllTracksPerformanceSelectionTests.swift`

**Interfaces:**
- Produces: `NativeTrackRowGeometry.init(rowHeight:)` with `titleFrame`, `artistFrame`, and `singleLineFrame` Y/height metrics.
- Produces: `TrackTableSelectionModifiers` and `prepareSelectionForContextMenu(row:modifiers:)`.
- Consumes: Task 1 native cell pointer/favorite presentation.

- [x] **Step 1: Add failing row geometry and no-outline tests.**

```swift
@Test("Track metadata shares the title line while artist stays below")
func nativeTrackRowGeometryAlignsMetadata() {
    let geometry = NativeTrackRowGeometry(rowHeight: 58)
    #expect(geometry.titleFrame.midY == geometry.singleLineFrame.midY)
    #expect(geometry.artistFrame.maxY < geometry.titleFrame.minY)
    #expect(abs(geometry.contentBounds.midY - geometry.twoLineBounds.midY) < 0.5)
}

@Test("Selected native rows use fill without an outline")
func nativeSelectionHasNoOutline() {
    let selected = NativeTrackTableChromePresentation.resolve(
        isSelected: true,
        isFocused: true,
        isHovered: false,
        isLiveScrolling: false,
        isFavorite: false
    )
    #expect(selected.fill == .selection)
    #expect(selected.outline == .clear)
}
```

- [x] **Step 2: Add failing modifier and context-click tests using a real coordinator/table.**

```swift
@Test("Control and Command both toggle one selected track")
func nativeAdditiveModifiers() {
    #expect(TrackTableSelectionModifiers([.control]).isAdditive)
    #expect(TrackTableSelectionModifiers([.command]).isAdditive)
    #expect(!TrackTableSelectionModifiers([]).isAdditive)
}

@Test("Modified context click extends selection before bulk menu resolution")
func contextClickExtendsSelection() {
    let current = IndexSet(integer: 0)
    #expect(TrackTableContextSelection.resolve(
        clickedRow: 2,
        selectedRows: current,
        modifiers: TrackTableSelectionModifiers([.control])
    ) == IndexSet([0, 2]))
}
```

- [x] **Step 3: Run the focused suites and confirm RED.**

Use the Task 1 AppKit command and add `-only-testing:CadenceTests/AllTracksPerformanceSelectionTests`. Expected: outline expectation fails and new policies are missing.

- [x] **Step 4: Implement geometry and apply it to every text column.**

```swift
struct NativeTrackRowGeometry: Equatable, Sendable {
    let contentBounds: CGRect
    let twoLineBounds: CGRect
    let titleFrame: CGRect
    let artistFrame: CGRect
    let singleLineFrame: CGRect

    init(rowHeight: CGFloat) {
        let lineHeight: CGFloat = 19
        let lineGap: CGFloat = 2
        let stackHeight = lineHeight * 2 + lineGap
        let stackY = (rowHeight - stackHeight) / 2
        contentBounds = CGRect(x: 0, y: 0, width: 0, height: rowHeight)
        artistFrame = CGRect(x: 0, y: stackY, width: 0, height: lineHeight)
        titleFrame = CGRect(x: 0, y: stackY + lineHeight + lineGap, width: 0, height: lineHeight)
        twoLineBounds = CGRect(x: 0, y: stackY, width: 0, height: stackHeight)
        singleLineFrame = titleFrame
    }
}
```

Use geometry Y/height for title, artist, album, year, and time; preserve each existing X/width and intrinsic metadata hit region. Resolve selected outline to `.clear` and set border width to zero.

- [x] **Step 5: Implement explicit modifiers and context-menu selection.**

```swift
struct TrackTableSelectionModifiers: Equatable, Sendable {
    let isRange: Bool
    let isAdditive: Bool

    init(_ flags: NSEvent.ModifierFlags) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        isRange = flags.contains(.shift)
        isAdditive = flags.contains(.command) || flags.contains(.control)
    }
}

enum TrackTableContextSelection {
    static func resolve(
        clickedRow: Int,
        selectedRows: IndexSet,
        modifiers: TrackTableSelectionModifiers
    ) -> IndexSet {
        if modifiers.isAdditive {
            var result = selectedRows
            result.formSymmetricDifference(IndexSet(integer: clickedRow))
            return result
        }
        return selectedRows.contains(clickedRow)
            ? selectedRows
            : IndexSet(integer: clickedRow)
    }
}
```

Change `select(row:)` to accept explicit flags with current-event default. Change the native context callback to `(UUID, NSEvent) -> NSMenu?`; before building the menu, preserve an already selected row, otherwise apply plain or additive selection from the event.

- [x] **Step 6: Re-run focused suites and confirm GREEN.**

Expected: title/album/year/time share one line, selected rows have no border, and modified context menus see the complete selected ID set.

- [x] **Step 7: Record checkpoint without committing.**

---

### Task 3: Catalog Multi-selection, Sort Controls, and Static Symbols

**Files:**
- Create: `Sources/Cadence/Models/CatalogSelection.swift`
- Create: `Sources/Cadence/Components/CatalogSortMenu.swift`
- Modify: `Sources/Cadence/App/CadenceAppModel.swift`
- Modify: `Sources/Cadence/Features/Albums/ProductionAlbumsView.swift`
- Modify: `Sources/Cadence/Features/Artists/ProductionArtistsView.swift`
- Modify: `Sources/Cadence/Features/Playlists/PlaylistsView.swift`
- Modify: `Sources/Cadence/Components/BrowserRowSurface.swift`
- Modify: `Sources/Cadence/Features/Home/ProductionHomeSupport.swift`
- Test: `Tests/CadenceTests/TrackSelectionControllerTests.swift`
- Test: `Tests/CadenceTests/LibraryUXInfrastructureTests.swift`

**Interfaces:**
- Produces: `CatalogSelectionAction` and `CatalogActivationSelection.handle(_:orderedTargets:modifiers:)`.
- Produces: `CatalogSortMenu<Field: Identifiable & Hashable>` with field/direction bindings.
- Produces: `CatalogSortSelection<Field>.select(field:)` and `.select(direction:)` for direct menu state.
- Consumes: `CatalogActivationTarget(kind:id:)` and existing AppStorage sort keys.

- [x] **Step 1: Add failing catalog selection tests.**

```swift
@Test("Catalog plain, additive, range, and activation actions use stable targets")
func catalogModifierSelection() {
    let targets = (0 ..< 4).map {
        CatalogActivationTarget(kind: .album, id: deterministicUUID(82000 + $0))
    }
    var selection = CatalogActivationSelection()
    #expect(selection.handle(targets[1], orderedTargets: targets, modifiers: []) == .activate)
    #expect(selection.handle(targets[3], orderedTargets: targets, modifiers: [.control]) == .selected)
    #expect(selection.targets == Set([targets[1], targets[3]]))
    #expect(selection.handle(targets[2], orderedTargets: targets, modifiers: [.shift]) == .selected)
    #expect(selection.targets == Set([targets[1], targets[2]]))
    #expect(selection.handle(targets[2], orderedTargets: targets, modifiers: []) == .activate)
}
```

Add a second test proving switching from `.album` to `.artist` replaces the set and modifier actions never activate.

- [x] **Step 2: Run `TrackSelectionControllerTests` and confirm RED.**

Run:

```bash
DEVELOPER_DIR='/Applications/Developing & Coding/Xcode.app/Contents/Developer' xcodebuild -project Cadence.xcodeproj -scheme Cadence -configuration Debug -derivedDataPath .build/DerivedData -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:CadenceTests/TrackSelectionControllerTests test
```

Expected: the multi-target API is absent.

- [x] **Step 3: Implement catalog selection and wire albums/artists/playlists.**

```swift
enum CatalogSelectionAction: Equatable, Sendable { case selected, activate }

struct CatalogActivationSelection: Equatable, Sendable {
    private(set) var targets: Set<CatalogActivationTarget> = []
    private(set) var primary: CatalogActivationTarget?
    private(set) var anchor: CatalogActivationTarget?

    func contains(_ target: CatalogActivationTarget) -> Bool { targets.contains(target) }
}
```

The mutating handler implements plain replace-and-activate, Command-or-Control toggle without activation, Shift range within `orderedTargets`, kind change replacement, primary fallback, and anchor maintenance. Album/artist tile actions pass `NSApp.currentEvent` flags and sorted visible targets. Playlist modifier actions update catalog selection; an unmodified primary selection still calls `store.selectPlaylist` so the detail pane loads.

- [x] **Step 4: Add direct sort control and static-symbol failing checks.**

Add behavior tests for a pure `CatalogSortSelection` resolver that changes field without nesting and toggles direction explicitly. Add a narrow presentation contract test that `CadenceRowButtonStyle` resolves pressed opacity without a symbol-effect trigger and `HomeTrackTile` resolves no accessory.

- [x] **Step 5: Implement shared direct menu and remove symbol motion/track triangle.**

`CatalogSortMenu` directly emits field buttons, a divider, and Ascending/Descending buttons, with checkmarks for active values. Replace both nested menus. Remove `.symbolEffect` and animated pressed-state interpolation from `CadenceRowButtonStyle`; keep immediate opacity. Make `HomeMediaTile.accessorySymbol` optional and pass `nil` from `HomeTrackTile`.

- [x] **Step 6: Regenerate Xcode project and run focused GREEN suites.**

```bash
xcodegen generate --spec project.yml
DEVELOPER_DIR='/Applications/Developing & Coding/Xcode.app/Contents/Developer' xcodebuild -project Cadence.xcodeproj -scheme Cadence -configuration Debug -derivedDataPath .build/DerivedData -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:CadenceTests/TrackSelectionControllerTests -only-testing:CadenceTests/LibraryUXInfrastructureTests test
```

- [x] **Step 7: Record checkpoint without committing.**

---

### Task 4: Typed Home Pins and Artist Pin Action

**Files:**
- Modify: `Sources/Cadence/Features/Artists/ProductionArtistsView.swift`
- Modify: `Sources/Cadence/Features/Home/ProductionHomeView+Sections.swift`
- Test: `Tests/CadenceTests/LibraryUXInfrastructureTests.swift`

**Interfaces:**
- Produces: `HomePinnedSection<Item>` projections or equivalent typed shelf inputs.
- Consumes: existing `HomePinStore.orderedIDs(for:)`, `pinRevision`, and Task 3 tile selection.

- [x] **Step 1: Add a failing typed projection test.**

```swift
@Test("Home pin projections remain separated by media kind")
func homePinsAreGroupedByKind() {
    let sections = HomePinnedSectionKind.visibleKinds(
        albumCount: 1,
        artistCount: 2,
        playlistCount: 1,
        smartCollectionCount: 0
    )
    #expect(sections == [.albums, .artists, .playlists])
    #expect(sections.map(\.title) == ["Pinned Albums", "Pinned Artists", "Pinned Playlists"])
}
```

- [x] **Step 2: Run `LibraryUXInfrastructureTests` and confirm RED.**

- [x] **Step 3: Implement typed shelves and artist context pinning.**

Replace `Quick Access` with one conditional `HomeShelf` per kind, preserving `HomeCompactGrid` and per-kind ordering. Add the same `HomePinStore.contains/toggle` button used by albums to `artistActions`.

- [x] **Step 4: Run focused tests and confirm GREEN.**

- [x] **Step 5: Record checkpoint without committing.**

---

### Task 5: Named Playlist Creation from Captured Track Selection

**Files:**
- Modify: `Sources/Cadence/App/CadenceAppModel.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore+Playlists.swift`
- Modify: `Sources/Cadence/Features/Playlists/AddToPlaylistMenuItems.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoordinator+Actions.swift`
- Modify: `Sources/Cadence/Features/Shell/CadenceRootView.swift`
- Test: `Tests/CadenceTests/LibraryStoreTests.swift`
- Test: `Tests/CadenceTests/LibraryUXInfrastructureTests.swift`

**Interfaces:**
- Produces: `PendingPlaylistCreation(trackIDs:name:)` and model request/cancel/confirm methods.
- Changes: `LibraryStore.createPlaylist(name:) async -> LibraryPlaylistProjection?`.
- Consumes: Task 2 `orderedSelectedIDs()` and existing `addToPlaylist(playlistID:trackIDs:)`.

- [x] **Step 1: Add failing store-return and request-state tests.**

```swift
@Test("Creating a playlist returns the created stable ID")
func createPlaylistReturnsProjection() async throws {
    let store = LibraryStore(container: try makeContainer(trackCount: 1))
    await store.loadInitialLibrary()
    let created = await store.createPlaylist(name: "Night Drive")
    #expect(created?.name == "Night Drive")
    #expect(store.playlists.contains { $0.id == created?.id })
}

@Test("Named playlist request captures track IDs and cancel persists nothing")
func pendingPlaylistCreationCapturesSelection() {
    let ids = [UUID(), UUID()]
    let model = CadenceAppModel.testFixture()
    model.requestPlaylistCreation(adding: ids)
    #expect(model.pendingPlaylistCreation?.trackIDs == ids)
    model.cancelPlaylistCreation()
    #expect(model.pendingPlaylistCreation == nil)
}
```

- [x] **Step 2: Run focused store/infrastructure suites and confirm RED.**

- [x] **Step 3: Return the created projection without relying on selected playlist state.**

Change all early exits and failures to `return nil`, return the captured projection after refreshing, and keep `selectedPlaylistID = playlist.id` for existing UI behavior.

- [x] **Step 4: Implement model-owned request and root alert.**

```swift
struct PendingPlaylistCreation: Equatable, Sendable {
    let trackIDs: [UUID]
    var name = ""
}
```

The root alert binds to the request name, disables Create for a trimmed empty name, calls an async confirm that creates then adds using `created.id`, and offers Cancel. Both AppKit and SwiftUI New Playlist actions call `requestPlaylistCreation(adding:)` and never call `createPlaylist()` immediately.

- [x] **Step 5: Run focused suites and confirm GREEN, including failure preservation.**

- [x] **Step 6: Record checkpoint without committing.**

---

### Task 6: Smart Collections Loading Ownership

**Files:**
- Modify: `Sources/Cadence/Features/Shell/CadenceRootView.swift`
- Test: `Tests/CadenceTests/LibraryUXInfrastructureTests.swift`

**Interfaces:**
- Produces: `DestinationPresentation.resolve(destination:hasResidentContent:isLoading:)`.
- Consumes: existing `DestinationPresentation.resolve(hasResidentContent:isLoading:)`.

- [x] **Step 1: Add the failing deadlock regression.**

```swift
@Test("Smart Collections mounts while its page-owned data task is loading")
func smartCollectionsDoesNotDeadlockRootPresentation() {
    #expect(DestinationPresentation.resolve(
        destination: .smartCollections,
        hasResidentContent: false,
        isLoading: true
    ) == .content)
}
```

Keep the existing generic three-case loading test for destinations whose loads are root-owned.

- [x] **Step 2: Run `LibraryUXInfrastructureTests` and confirm RED.**

- [x] **Step 3: Implement destination-aware resolution.**

Smart Collections always resolves root presentation to `.content`; its `SmartCollectionsView` tasks and internal regions retain loading/error/empty behavior. Do not mark every empty destination resident.

- [x] **Step 4: Run focused tests and confirm GREEN.**

- [x] **Step 5: Record checkpoint without committing.**

---

### Task 7: Cadence Mode Hint, Native Back, and Lyrics Presentation Clock

**Files:**
- Modify: `Sources/Cadence/Features/NowPlaying/ProductionNowPlayingView.swift`
- Modify: `Sources/Cadence/Features/LyricsEditor/TapToSyncPanel.swift`
- Test: `Tests/CadenceTests/CadenceModeLayoutTests.swift`
- Test: `Tests/CadenceTests/ProductionPlaybackAppModelTests.swift`

**Interfaces:**
- Produces: `LyricsEditorClockPresentation.time(model:hostUptime:)` or equivalent pure formatter input.
- Consumes: `CadenceAppModel.playbackPresentationTime(atHostUptime:)`, `LyricTimestampFormatter.display`, and existing native Back style.

- [x] **Step 1: Add failing clock-source and short-layout tests.**

```swift
@Test("Lyrics editor clock uses presentation time rather than progress")
func lyricsEditorClockUsesPresentationClock() {
    let presentation = LyricsEditorClockPresentation.resolve(
        stateTime: 51,
        presentationTime: 51.792,
        isPlaying: true
    )
    #expect(presentation == "0:51.792")
}

@Test("Now Playing context reserves a complete Cadence Mode hint")
func standardContextFitsShortWorkspace() {
    let policy = NowPlayingContextOverflowPolicy(height: 560)
    #expect(policy.usesVerticalScrolling)
    #expect(policy.bottomContentInset >= 24)
}
```

- [x] **Step 2: Run playback and Cadence layout suites and confirm RED.**

- [x] **Step 3: Make the track context vertically bounded.**

Wrap track-context content in a vertical `ScrollView`, preserve top alignment and 42-point horizontal/top inset, add bottom content inset, and use hidden automatic scroller presentation where supported. Keep artwork size from `CadenceModeLayout.standardArtworkFrame`.

- [x] **Step 4: Replace the bespoke Back capsule with the established control.**

```swift
Button {
    cadenceModeSession.deactivate()
} label: {
    Label("Back to Now Playing", systemImage: "chevron.left")
}
.buttonStyle(.plain)
.foregroundStyle(.secondary)
```

Keep top-leading placement, help, and dark-mode readability.

- [x] **Step 5: Render the editor clock from a periodic timeline.**

While playing, use `TimelineView(.periodic(from: .now, by: 1.0 / 30.0))`; resolve `model.playbackPresentationTime(atHostUptime:)`. While paused, resolve `model.playbackCurrentTime`. Keep monospaced digits and reserve the width of `0:00.000` or a wider duration-derived sample.

- [x] **Step 6: Run focused suites and confirm GREEN.**

- [x] **Step 7: Record checkpoint without committing.**

---

### Task 8: Native Settings Switches and Integrated Verification

**Files:**
- Modify: `Sources/Cadence/Features/Settings/ProductionSettingsView.swift`
- Modify: `Tests/CadenceTests/LibraryUXInfrastructureTests.swift`
- Modify: `Cadence.xcodeproj/project.pbxproj`
- Inspect: all files from Tasks 1-7

**Interfaces:**
- Consumes: every earlier task's public policy and UI state.
- Produces: final locally verified uncommitted change set.

- [x] **Step 1: Add a failing settings presentation test.**

Prefer a view-level inspection hook if the existing test infrastructure can read environment style. If it cannot, add a small pure policy:

```swift
enum SettingsBooleanControlStyle: Equatable, Sendable { case nativeSwitch }

@Test("Persistent Settings booleans use native switches")
func settingsBooleanStyle() {
    #expect(SettingsBooleanControlPresentation.style == .nativeSwitch)
}
```

The runtime consumer must apply `.toggleStyle(.switch)` to the entire `ProductionSettingsView` subtree; the policy test cannot be the only link.

- [x] **Step 2: Run `LibraryUXInfrastructureTests` and confirm RED.**

- [x] **Step 3: Apply native switch style and run focused GREEN tests.**

Add `.toggleStyle(.switch)` at the root of `ProductionSettingsView`, covering Sidebar, Cadence Mode, and Updates settings without changing segmented pickers.

- [x] **Step 4: Regenerate the Xcode project and run formatting checks.**

```bash
xcodegen generate --spec project.yml
swiftformat Sources Tests
swiftformat Sources Tests --lint
swiftlint lint --config .swiftlint.yml --cache-path .build/swiftlint-cache
git diff --check
```

- [x] **Step 5: Run all focused suites together.**

```bash
DEVELOPER_DIR='/Applications/Developing & Coding/Xcode.app/Contents/Developer' xcodebuild -project Cadence.xcodeproj -scheme Cadence -configuration Debug -derivedDataPath .build/DerivedData -destination 'platform=macOS' -jobs 2 -parallel-testing-enabled NO -only-testing:CadenceTests/AllTracksPerformanceTests -only-testing:CadenceTests/AllTracksPerformanceSelectionTests -only-testing:CadenceTests/TrackSelectionControllerTests -only-testing:CadenceTests/LibraryUXInfrastructureTests -only-testing:CadenceTests/LibraryStoreTests -only-testing:CadenceTests/ProductionPlaybackAppModelTests -only-testing:CadenceTests/CadenceModeLayoutTests test
```

- [x] **Step 6: Render temporary visual acceptance frames.**

Use the existing documentation screenshot harness with a temporary output override. Capture and inspect: idle/scrolled hearts, wide and minimum track rows, multi-selection, album sort menu, typed Home pins, short Now Playing hint, Cadence Mode Back, lyrics editor clock, and Settings switches. Do not run `scripts/update_screenshots.sh` against tracked baselines.

- [x] **Step 7: Run the complete gate once.**

```bash
DEVELOPER_DIR='/Applications/Developing & Coding/Xcode.app/Contents/Developer' bash scripts/verify.sh
```

Expected: complete success, including project generation, release-contract tests, formatting, lint, all Cadence tests, localization, Periphery, and built-product checks.

- [x] **Step 8: Audit requirement coverage and final diff.**

Map TRK-01 through SET-01 to tests and visual/manual evidence. Run `git status --short`, `git diff --stat`, and `git diff --check`. Confirm no tracked baseline, user-library, release, or unrelated file changed.

- [x] **Step 9: Report manual-only acceptance separately.**

List pointer-stationary scrolling, Control/Command context click, actual alert focus, and perceived absence of animation as manual checks unless directly exercised through a live app session. Do not claim them from build/test output alone.
