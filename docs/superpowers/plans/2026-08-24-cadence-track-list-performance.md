# Cadence Track-List Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every potentially large Cadence track list scroll with bounded main-thread work, using a reusable layer-backed AppKit row while preserving current behavior and accessibility.

**Architecture:** Keep `NSTableView` as the virtualization and interaction owner. Convert library values once into immutable display projections, configure a stable native AppKit cell hierarchy, route commands by stable identity, and feed the table from bounded paged sources. Treat Core Animation as the compositing boundary, not as a substitute for eliminating synchronous work.

**Tech Stack:** Swift 6, AppKit, SwiftUI at screen boundaries, Core Animation, SwiftData, Swift Testing, XCTest/Xcode performance tooling.

**Spec:** `docs/superpowers/specs/2026-08-24-cadence-track-list-performance-design.md`

## Global Constraints

- [ ] Work in the existing `qenterra/cadence-release-recovery` checkout because its 174 uncommitted entries are part of the active implementation state; do not create an incomplete clean-room worktree.
- [ ] Preserve unrelated user changes and inspect every overlapping diff before editing.
- [ ] Use one reusable Derived Data directory under `/private/tmp` for focused builds; do not start concurrent builds or unbounded profiling loops.
- [ ] Follow RED → GREEN → REFACTOR for each production change.
- [ ] Do not commit, push, sign, notarize, publish, or mutate a real user library.
- [ ] Do not claim physical smoothness from an XCTest wall-clock threshold; manual trackpad and Instruments acceptance remains explicit.

## Task 1: Establish a truthful performance baseline

**Files:**

- Modify: `Tests/CadenceTests/AllTracksPerformanceTestSupport.swift`
- Modify: `Tests/CadenceTests/AllTracksPerformanceAppKitTests.swift`
- Modify: `Tests/CadenceTests/AllTracksPerformanceTests.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoordinator.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCore.swift`

- [ ] Add a failing test that distinguishes the 250 ms watchdog from smoothness acceptance and records incremental scroll deltas, cell creations, configurations, full reloads, and targeted reloads.
- [ ] Run only the focused performance suite and confirm the new contract fails for a missing event/counter implementation.
- [ ] Add deterministic `TrackTablePerformanceMetrics` counters and signposts with reset/snapshot APIs available to tests without retaining rows or artwork.
- [ ] Exercise a real `NSWindow`/`NSScrollView` using incremental origin changes and momentum-like bursts; record p50, p95, maximum row-configuration time, cell counts, and reload counts.
- [ ] Keep `scrollRowToVisible` as a regression probe, rename labels that imply physical smoothness, and make the watchdog failure message say “hang guard.”
- [ ] Re-run the focused suite and capture the baseline for the existing SwiftUI-hosted cell.

## Task 2: Build immutable preformatted row projections

**Files:**

- Create: `Sources/Cadence/Features/Library/TrackRowDisplayProjection.swift`
- Create: `Tests/CadenceTests/TrackRowDisplayProjectionTests.swift`
- Modify: `Sources/Cadence/Features/Library/ProductionTrackTable.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCore.swift`

- [ ] Add failing tests for title/artist/album fallback, codec/year/duration formatting, favorite/current/playing flags, artwork revision identity, and accessibility text.
- [ ] Add a mutation-isolation test proving a configured projection remains unchanged when the source model later changes.
- [ ] Implement `TrackRowDisplayProjection` as `Equatable` and `Sendable`; keep all display formatting out of the cell configuration path.
- [ ] Create projections at the table boundary and cache them by stable track identity plus relevant content/version state.
- [ ] Add counters asserting a scroll-only pass does not rebuild unchanged projections.
- [ ] Run projection and existing table-column tests.

## Task 3: Implement the native layer-backed reusable cell

**Files:**

- Create: `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`
- Create: `Tests/CadenceTests/NativeTrackTableCellTests.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoreViews.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableLayout.swift`

- [ ] Add a failing test requiring an `NSTableCellView` whose layer/subview identities survive repeated configuration and whose production subtree contains no `NSHostingView`.
- [ ] Add failing geometry tests for minimum, ideal, and wide widths across supported column combinations.
- [ ] Implement one stable hierarchy of non-editable `NSTextField`, native controls, and `CALayer`/`CAShapeLayer` surfaces; set `wantsLayer = true` once during initialization.
- [ ] Disable implicit layer actions during live scroll and Reduce Motion; do not enable `shouldRasterize` or `drawsAsynchronously` without a measured win.
- [ ] Update only changed properties during configuration and avoid constraints/subview creation after initialization.
- [ ] Re-run cell tests and the incremental-scroll benchmark; require reuse count to grow while creation count stays bounded by the visible/overscan set.

## Task 4: Restore interaction and accessibility parity

**Files:**

- Create: `Sources/Cadence/Features/Library/TrackTableRowActionRouter.swift`
- Create: `Tests/CadenceTests/TrackTableRowActionRouterTests.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoordinator+Actions.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoordinator.swift`
- Modify: `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`
- Reference: `Sources/Cadence/Features/Library/ProductionTrackTableRow.swift`

- [ ] Add failing tests that reuse one cell across two tracks and prove favorite/play/menu/navigation actions resolve the current stable ID, never the prior row.
- [ ] Add failing tests for selection, hover, focus, keyboard activation, tooltips, accessibility labels/actions, context menu, and drag/drop payload identity.
- [ ] Implement typed action routing owned by the coordinator; cells expose IDs and events but never retain `CadenceAppModel`.
- [ ] Build expensive menus lazily on invocation and preserve multi-selection semantics.
- [ ] Make selection/current-track/favorite updates targeted row reconfiguration, not full table reloads.
- [ ] Run action, selection, viewport, and accessibility-focused suites.

## Task 5: Integrate artwork with bounded memory and stale-result rejection

**Files:**

- Modify: `Sources/Cadence/Components/ArtworkView.swift`
- Modify: `Sources/Cadence/Components/ProductionArtworkView.swift`
- Modify: `Sources/Cadence/Persistence/ArtworkAssetCache.swift`
- Modify: `Sources/Cadence/Features/Library/NativeTrackTableCell.swift`
- Create: `Tests/CadenceTests/NativeTrackTableArtworkTests.swift`
- Modify: `Tests/CadenceTests/ArtworkAssetCacheTests.swift`

- [ ] Add a failing rapid-reuse test where track A artwork completes after the cell already represents track B; assert A is discarded.
- [ ] Add failing cold/warm/duplicate-artwork tests that record request, hit, miss, decode, publication, and stale-rejection counts.
- [ ] Configure artwork by track ID, revision, variant, and cell generation; cancel stale observation on reuse.
- [ ] Assign the bounded decoded image to the layer at the window backing scale without main-actor decode or per-frame resampling.
- [ ] Enforce cost-based decoded-byte limits and a deterministic plateau after repeated down/up traversal.
- [ ] Re-run artwork and incremental-scroll suites, comparing cold and warm runs.

## Task 6: Switch the production hot path and remove full reloads for local changes

**Files:**

- Modify: `Sources/Cadence/Features/Library/TrackTableCore.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoordinator.swift`
- Modify: `Sources/Cadence/Features/Library/ProductionTrackTable.swift`
- Modify: `Sources/Cadence/Features/Library/ProductionTrackTableRow.swift`
- Modify: `Tests/CadenceTests/AllTracksPerformanceHostingTests.swift`
- Modify: `Tests/CadenceTests/AllTracksPerformanceAppKitTests.swift`

- [ ] Add a failing production-factory test requiring `NativeTrackTableCell` for real rows while keeping the hosted row only as a reference fixture.
- [ ] Extend the update planner tests so append, one-row mutation, selection, current-track, and favorite changes cannot select `reloadData()`.
- [ ] Switch coordinator cell creation/configuration to the native cell and display projection.
- [ ] Implement `insertRows`, `removeRows`, `moveRow`, and targeted `reloadData(forRowIndexes:columnIndexes:)` plans with stable-ID validation and safe full-reload fallback only for incompatible source replacement.
- [ ] Re-run table behavior, viewport, selection, and both renderer performance suites.

## Task 7: Generalize bounded sources to every potentially large list

**Files:**

- Modify: `Sources/Cadence/Features/Library/NativeAllTracksTable.swift`
- Modify: `Sources/Cadence/Features/Library/AllTracksView.swift`
- Modify: `Sources/Cadence/Features/Library/LibraryFavoritesView.swift`
- Modify: `Sources/Cadence/Features/Playlists/PlaylistsView+Presentation.swift`
- Modify: `Sources/Cadence/Features/Search/ProductionSearchResultsView.swift`
- Modify: `Sources/Cadence/Features/SmartCollections/SmartCollectionResultsColumn.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore+FavoritePagination.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore+Browser.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore+CatalogSearch.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore+Playlists.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore+SmartCollections.swift`
- Create: `Tests/CadenceTests/TrackTableBoundedSourceTests.swift`

- [ ] Add failing source tests for Favorites, browser, playlists, expanded search, and Smart Collections using large synthetic counts; assert constant page capacity, cancellation, stale rejection, and bounded published row count.
- [ ] Extract the existing All Tracks page-window policy behind a shared typed source contract without changing All Tracks behavior.
- [ ] Migrate one screen at a time, running its focused behavior tests after each migration.
- [ ] Preserve playlist ordered-ID reordering and validate that page invalidation cannot corrupt drag/drop order.
- [ ] Assert page append exposes/inserts only affected rows and never triggers a full table reload.
- [ ] Run all list/source suites together.

## Task 8: Measure and fix real deep SwiftData paging

**Files:**

- Modify: `Sources/Cadence/Persistence/LibraryStore+TrackPaging.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStoreTypes.swift`
- Create: `Tests/CadenceTests/LibraryStoreDeepPagingPerformanceTests.swift`
- Modify: `Tests/CadenceTests/LibraryStoreTests.swift`

- [ ] Add a deterministic on-disk fixture benchmark for shallow/middle/deep pages under every supported sort; do not substitute a fake loader.
- [ ] Record query time and verify fetch/decode/publish stays off the main actor.
- [ ] If deep offset cost breaches the measured budget, add a stable ordered anchor/index snapshot keyed by query identity and content version, with invalidation tests.
- [ ] Preserve random access for scrollbar jumps and prove cancellation/stale generation behavior.
- [ ] Re-run deep paging, million-row window, and source integration suites.

## Task 9: Verification and acceptance boundary

**Files:**

- Modify: `docs/superpowers/specs/2026-08-24-cadence-track-list-performance-design.md` only if implementation evidence changes the contract.
- Create: `docs/verification/2026-08-24-track-list-performance.md`

- [ ] Run strict Swift 6 build once with the shared Derived Data directory.
- [ ] Run all focused track-table, list-source, artwork, paging, selection, viewport, and accessibility suites.
- [ ] Run `scripts/verify.sh` once after focused gates pass.
- [ ] Run the real-window incremental event stream and report p50/p95/max, cell creation/reuse, projection count, reload count, and cache plateau before/after.
- [ ] Inspect the final diff for accidental changes, placeholder text, broad reloads, per-row model retention, synchronous artwork work, unbounded caches, and unapproved repository operations.
- [ ] Record automated evidence separately from the still-required physical trackpad, VoiceOver/Switch Control, and Instruments Hitches/Allocations/Core Animation acceptance.
