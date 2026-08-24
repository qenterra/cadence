# Cadence Track and Catalog Coherence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Stabilize track-table geometry and interaction, catalog card sizing,
Favorites switching, Sidebar ordering, and Recently Played ordering.

**Architecture:** Keep the existing native AppKit track table and route every
visual decision through pure presentation policies. Remove transient-state
leaks at the reusable-cell boundary, use fixed grid metrics for catalog cards,
and make reorder/recent-play mutations explicit value operations.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Swift Testing, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-24-cadence-interface-coherence-design.md`

## Global Constraints

- Implement CUI-01 through CUI-12 and CUI-15 exactly as specified.
- Follow RED -> GREEN -> REFACTOR for every production behavior.
- Keep `NSTableView` virtualization and stable-ID action routing.
- Do not restore codec/LRC row pills; their removal is authoritative.
- Do not commit, push, merge, or update screenshot baselines.

---

### Task 1: Deterministic non-resizable track columns

**Files:**

- Modify: `Tests/CadenceTests/TrackTableColumnPolicyTests.swift`
- Modify: `Tests/CadenceTests/SecondAuditPresentationTests.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableColumnPolicy.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableLayout.swift`
- Modify: `Sources/Cadence/Features/Library/ProductionTrackTable.swift`

**Interfaces:**

- Produces: `TrackTableColumnPolicy.layout(availableWidth:columns:)`
- Produces: sortable `TrackTableHeaderCell` with no width binding or drag state.

- [x] **Step 1: Write the failing geometry tests.** Assert literal supported
  widths: album `190`, year `64`, time `64`; Track receives the remainder and
  never falls below `360` at the minimum full-table viewport. Add a compact
  test proving optional columns disappear before active columns are crushed.
- [x] **Step 2: Run `TrackTableColumnPolicyTests` and confirm failures are from
  the old adaptive/resizable contract.**
- [x] **Step 3: Remove preferred-width input, proportional scaling, AppStorage
  widths, drag handles, cursor/resizer state, and adjustable-width accessibility
  actions.** Keep header sort buttons and sort direction semantics.
- [x] **Step 4: Run the focused tests and existing table-layout tests.**

### Task 2: Native row identity, title budget, and metadata removal

**Files:**

- Modify: `Tests/CadenceTests/NativeTrackTableCellTests.swift`
- Modify: `Tests/CadenceTests/TrackRowDisplayProjectionTests.swift`
- Modify: `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`
- Modify: `Sources/Cadence/Features/Library/TrackRowDisplayProjection.swift`
- Modify: `Sources/Cadence/Features/Library/ProductionTrackTableRowSupport.swift`

**Interfaces:**

- Produces: `NativeTrackTableCell.configure(...)` resets transient state when
  `representedTrackID` changes.
- Produces: title frame equal to the remaining song-metadata rectangle.

- [x] **Step 1: Add a failing reuse test.** Configure one cell for A, call its
  hover entry, configure for B, and assert B's non-favorite control is hidden
  until B receives its own hover event.
- [x] **Step 2: Add a failing layout test.** Hand-derive the title frame for a
  400-point Track column and assert it consumes all width after artwork and
  spacing rather than `0.62 * width`.
- [x] **Step 3: Add a failing projection/cell test asserting codec and LRC
  labels are absent from production row content while explicit state remains.**
- [x] **Step 4: Run the tests and confirm each fails for the named old branch.**
- [x] **Step 5: Reset hover/press on identity change, remove the percentage cap,
  and remove codec/LRC row subviews and SwiftUI fallback badges.**
- [x] **Step 6: Run native-cell, row-projection, and hosted-row parity suites.**

### Task 3: Text-only album/artist links and Cadence row chrome

**Files:**

- Modify: `Tests/CadenceTests/NativeTrackTableCellTests.swift`
- Modify: `Tests/CadenceTests/TrackTableRowActionRouterTests.swift`
- Modify: `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`
- Modify: `Sources/Cadence/Components/BrowserRowSurface.swift`

**Interfaces:**

- Produces: intrinsic `artistButton` and `albumButton` frames with bounded
  control padding.
- Produces: pure `NativeTrackTableChromePresentation` for fill, border, text,
  and favorite tones.

- [x] **Step 1: Add failing geometry tests proving points outside rendered link
  text do not hit artist/album controls while points inside do.**
- [x] **Step 2: Add failing presentation tests asserting selection/focus never
  resolves to `selectedContentBackgroundColor`, `keyboardFocusIndicatorColor`,
  or `controlAccentColor`.**
- [x] **Step 3: Add failing hover/press tests: resting secondary, hovered
  primary, pressed unchanged; favorite tone is Cadence primary.**
- [x] **Step 4: Implement measured link frames and the Cadence chrome policy.**
  Suppress the default borderless-button pressed tint and retain keyboard and
  accessibility activation.
- [x] **Step 5: Run cell, action-router, selection, and accessibility tests.**

### Task 4: Favorite response and Favorites segmented type control

**Files:**

- Modify: `Tests/CadenceTests/FavoriteButtonTests.swift`
- Modify: `Tests/CadenceTests/LibraryFavoritesTests.swift`
- Modify: `Sources/Cadence/Components/FavoriteButton.swift`
- Modify: `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`
- Modify: `Sources/Cadence/Features/Library/LibraryFavoritesView.swift`

**Interfaces:**

- Produces: shared `FavoriteFeedbackState` keyed by stable item identity.
- Consumes: `LibraryFavoritesSection` selection.

- [x] **Step 1: Add failing state tests proving a successful toggle increments
  feedback only for the requested item and identity reuse resets it.**
- [x] **Step 2: Add a failing Favorites presentation test requiring one inline
  segmented Picker with Tracks, Albums, and Artists options.**
- [x] **Step 3: Implement a bounded scale/opacity response for SwiftUI and
  AppKit favorite controls; use only opacity/tone under Reduce Motion.**
- [x] **Step 4: Replace `Menu { Picker("Type") }` with a segmented Picker and
  preserve the selected section and saved-count copy.**
- [x] **Step 5: Run favorite and Favorites suites.**

### Task 5: Fixed catalog card metrics

**Files:**

- Create: `Sources/Cadence/DesignSystem/CatalogCardLayoutMetrics.swift`
- Create: `Tests/CadenceTests/CatalogCardLayoutMetricsTests.swift`
- Modify: `Sources/Cadence/Features/Albums/ProductionAlbumsView.swift`
- Modify: `Sources/Cadence/Features/Artists/ProductionArtistsView.swift`
- Modify: `Sources/Cadence/Features/Playlists/PlaylistsView+Presentation.swift`
- Modify: `Sources/Cadence/Features/Home/ProductionHomeSupport.swift`
- Modify: `Sources/Cadence/Features/Library/LibraryFavoritesView.swift`
- Modify: `Sources/Cadence/Features/Search/ProductionSearchResultsView.swift`

**Interfaces:**

- Produces: `CatalogCardLayoutMetrics.cardWidth: CGFloat == 196`
- Produces: `CatalogCardLayoutMetrics.columns(availableWidth:spacing:)` returning
  fixed `GridItem`s.

- [x] **Step 1: Add failing literal geometry tests.** For 640, 960, and 1280
  content widths, assert every returned item has a 196-point fixed size and
  only the number of columns changes.
- [x] **Step 2: Implement the shared metrics and migrate album, artist,
  playlist, Home, Favorites, and Search catalog grids.**
- [x] **Step 3: Run metric and existing layout/screenshot-structure tests.**

### Task 6: Flat Sidebar ordering and no icon motion

**Files:**

- Modify: `Tests/CadenceTests/NavigationRailTests.swift`
- Modify: `Tests/CadenceTests/SecondAuditPresentationTests.swift`
- Modify: `Sources/Cadence/Models/NavigationRailConfiguration.swift`
- Modify: `Sources/Cadence/Features/Settings/SettingsSidebarCard.swift`
- Modify: `Sources/Cadence/Components/NavigationRail.swift`

**Interfaces:**

- Produces: `NavigationRailConfiguration.moving(_:to:in:)` supporting any two
  configurable destinations while Home remains first.
- Produces: navigation icons with no activation counter or symbol transition.

- [x] **Step 1: Add failing reorder tests moving Tags before Albums and Artists
  after Import, while Home remains first and every destination stays unique.**
- [x] **Step 2: Add a failing presentation test proving activating any
  destination does not mutate icon-animation state.**
- [x] **Step 3: Flatten Settings Sidebar to one bordered list, remove group
  labels/restrictions, and compute Move Up/Down from the full order.**
- [x] **Step 4: Remove activation counts, `symbolEffect`, and replacement
  transitions from all destination icons, including the expansion icon.**
- [x] **Step 5: Run navigation ordering, accessibility, and settings tests.**

### Task 7: Recently Played stable move-to-front behavior

**Files:**

- Modify: `Tests/CadenceTests/LibraryStoreTests.swift`
- Modify: `Tests/CadenceTests/LibraryStoreEpochTests.swift`
- Modify: `Tests/CadenceTests/LibraryUXInfrastructureTests.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore+TrackPaging.swift`
- Modify: `Sources/Cadence/Features/Home/ProductionHomeView.swift`
- Modify: `Sources/Cadence/Features/Home/ProductionHomeView+Sections.swift`

**Interfaces:**

- Produces: recent result publication removes an existing ID, inserts its
  updated projection at index zero, and preserves repository ordering.
- Produces: Home recent selection no longer excludes current playback ID.

- [x] **Step 1: Add a failing store test starting with `[A, B, C]`, recording B,
  and asserting `[B, A, C]` with B's updated date and no duplicate.**
- [x] **Step 2: Add a failing Home selection test asserting the current track
  remains the first recent item.**
- [x] **Step 3: Implement move-to-front publication and remove the current-ID
  exclusion from Home recent/favorite shelf budgeting.**
- [x] **Step 4: Run recent-played, Home, and epoch-safety tests.**

### Task 8: Track/catalog verification checkpoint

**Files:**

- Create: `docs/verification/2026-08-24-interface-coherence.md`

- [x] Run all track-table, favorite, catalog-layout, navigation, Home, and
  accessibility focused tests.
- [x] Run SwiftFormat lint for touched Swift files.
- [x] Render minimum/default/wide temporary table and catalog frames without
  promoting tracked baselines; record remaining manual hit-testing checks.
