# Cadence Track-List Performance Design

## Objective

Make every Cadence track list remain responsive while scrolling, paging,
selecting, loading artwork, and receiving playback-state updates. Preserve the
native macOS table behavior and accessibility contract while replacing the
SwiftUI-hosted scrolling hot path with a bounded, layer-backed AppKit renderer.

This design specializes R-08, R-09, R-10, and R-20 from
`2026-08-22-cadence-release-recovery-spec.md`. That release-recovery
specification remains authoritative for product behavior and safety.

## Evidence Boundary

The current implementation already provides stable track UUIDs, an
`NSTableView` container, reused hosting cells, a bounded All Tracks window,
directional prefetch, request cancellation, a 128-pixel `trackRow` artwork
variant, and decoded-image caching.

The remaining performance risks are:

- every reused cell still updates a full `ProductionTrackTableRow` SwiftUI
  tree with root-model dependencies, controls, menus, focus state, gestures,
  and per-body display formatting;
- only All Tracks uses a bounded random-access window, while Favorites,
  browser results, playlists, search, and Smart Collections retain growing
  materialized arrays and can reload the complete table when a page appends;
- All Tracks uses offset paging, but the existing million-row test measures a
  fake loader rather than deep real SwiftData fetch cost;
- the live-scroll benchmark manually toggles scrolling state and performs
  `scrollRowToVisible` jumps, so it proves relative branch cost rather than
  physical trackpad frame pacing;
- cache limits and decode counters are deterministic, but live memory pressure
  and concurrent artwork completion during scrolling remain unmeasured.

These are verified implementation boundaries, not a claim that any one item is
the sole cause of the user's observed lag. The dominant runtime cause remains a
profiling result, not an assumption.

## Constraints

- Remain native macOS 26 or later and Swift 6 with the existing dependency set.
- Keep `NSTableView` as the owner of virtualization, selection, keyboard input,
  accessibility row semantics, drag and drop, and scroll position.
- Preserve the existing visual geometry, columns, hover/selection chrome,
  favorite behavior, action menus, queue semantics, contextual navigation,
  and Reduce Motion behavior.
- Preserve the bounded artwork variants and never decode artwork on the main
  actor during scrolling.
- Do not use the user's real library in automated tests.
- Do not add Metal or a custom text renderer. Core Animation layer backing is
  the hardware-accelerated boundary for the track-table hot path.
- Do not commit, push, sign, notarize, publish, or mutate external state.

## Considered Approaches

### 1. Continue optimizing the SwiftUI-hosted row

Keep `NSHostingView<ProductionTrackTableRow>` and replace its model dependency
with smaller values, preformat strings, and further suppress modifiers during
live scrolling.

This is the smallest diff and preserves the current declarative row, but it
continues to pay SwiftUI representable, dependency, focus, and tree-update cost
for every reused cell. The existing lightweight live-scroll branch already
demonstrates diminishing returns from this approach.

### 2. Native AppKit row with a Core Animation backing layer

Keep the existing `NSTableView` coordinator and replace the production hot
path with a reusable `NSTableCellView`. Configure stable `NSTextField`,
`NSImageView`, and button subviews from an immutable display projection. Use a
layer-backed surface for selection, hover, focus, and artwork compositing.
Create menus and expensive command content only when the user requests them.

This approach is selected. It removes SwiftUI row-tree work without replacing
the table, repository, selection, or command architecture. It is incremental:
the SwiftUI row remains available to deterministic comparison tests until the
native renderer reaches behavioral parity.

### 3. Custom Metal table renderer

Render text, artwork, selection, and controls in a Metal surface and build a
parallel input/accessibility model.

This could move more pixels through the GPU but does not solve data paging,
formatting, diffing, or main-actor publications. It would replace mature AppKit
text, focus, menus, drag and drop, and accessibility with bespoke code. The
cost and regression surface are disproportionate, so this approach is
rejected.

## Selected Architecture

### Immutable row display projection

Introduce `TrackRowDisplayProjection`, a small `Equatable` and `Sendable`
value derived when repository projections enter the table boundary. It owns
the exact strings and visual flags needed by a row:

- stable track, artist, album, and artwork identities;
- title, artist, album, codec, year, and duration display strings;
- favorite, explicit, synchronized-lyrics, current-track, and playing flags;
- artwork request key including ID, revision, and variant;
- per-row accessibility labels.

Rows never receive `CadenceAppModel`. User actions leave the cell as typed
commands carrying stable IDs. The coordinator or action router resolves those
commands against the current model and current selection.

### Native reusable cell

Add `NativeTrackTableCell`, created once per AppKit reuse slot. Its subview and
layer hierarchy remains stable across track changes. Configuration updates
text, visibility, colors, image contents, and control targets without replacing
the subtree.

The cell is layer-backed. Selection, hover, and focus use a stable
`CALayer`/`CAShapeLayer` surface with implicit animations disabled during live
scrolling and when Reduce Motion is enabled. Artwork is assigned as decoded
`CGImage` contents at the correct backing scale. Layer backing accelerates
compositing; it is not used to conceal synchronous layout or I/O.

The coordinator remains the owner of row selection and keyboard actions.
Favorite, play, album, artist, action-menu, context-menu, drag, drop, and help
behavior route through explicit closures or a `TrackTableRowActionRouter`.

### Shared bounded list source

Generalize `LibraryTrackWindow` into the production source for every
potentially large track list. A source supplies:

- total row count;
- query/source identity and content version;
- a bounded page window;
- row lookup by index and track ID;
- directional prefetch and cancellation;
- targeted replacement by stable ID;
- typed invalidation distinguishing source replacement, row mutation, insert,
  removal, and reorder.

All Tracks, Favorites, browser results, playlists, expanded search, and Smart
Collections adopt the source incrementally. Appending a page inserts or
reveals only the affected rows; it never calls a full `reloadData()` merely
because the materialized count grew.

Playlist reordering retains a stable ordered-ID source because random-access
drag and drop cannot be implemented safely with a forward-only cursor.

### Paging and repository contract

Keep random-access page lookup for native scrollbar jumps, but measure real
SwiftData offset cost for shallow and deep pages under every supported sort.
Where an indexed offset fetch exceeds the declared budget, introduce a stable
ordered anchor/index snapshot for that query rather than silently replacing
random access with forward-only cursor paging.

Every request carries query identity, generation, and page token. Cancelled or
stale loads cannot publish into the active window. Repository work remains off
the main actor; only the bounded result projection is published on the main
actor.

### Artwork pipeline and memory budget

Retain the `trackRow` variant and revision-aware compressed and decoded caches.
The native cell requests artwork through a coordinator-owned loader keyed by
track identity and cell generation. Reuse cancels observation of stale work;
an older completion cannot update a newer represented track.

Use cost-based cache limits based on decoded pixel bytes, not only compressed
data size. Measure cold, warm, duplicate-artwork, and rapid-reuse scenarios.
Memory acceptance requires a bounded plateau after repeated down/up scrolling,
not merely eventual cache eviction.

### Instrumentation and performance contract

Add signposts and deterministic counters for:

- live-scroll begin/end and visible-range changes;
- cell creation, reuse, configuration, and identity changes;
- row display-projection creation;
- page request, cancellation, completion, and stale rejection;
- artwork request, cache hit/miss, decode, publication, and stale rejection;
- full-table and targeted reloads.

The deterministic suite retains `scrollRowToVisible` as a regression probe but
does not call it live acceptance. A real-window automated event stream must
exercise incremental scroll deltas and momentum-like bursts. A native manual
trackpad trace remains required for physical frame pacing.

At 60 Hz, the complete main-thread preparation for a frame has 16.67 ms; at
120 Hz it has 8.33 ms. Automated gates therefore assert bounded work and no
individual Cadence row configuration above 1 ms after warm-up, while
Instruments Hitches and the display refresh interval remain the final runtime
authority. The existing 250 ms watchdog is retained only as a deadlock/hang
guard and is never described as a smoothness threshold.

## Error Handling

- A missing page renders the existing fixed-height placeholder and requests
  only the containing page.
- A failed page preserves the last valid rows, exposes retry state through the
  owning screen, and does not clear unrelated cached pages.
- A failed artwork request keeps the fixed-size placeholder and records one
  bounded failure; it does not retry on every cell configuration.
- A stale row, page, or artwork result is discarded by identity and generation
  before UI publication.
- A native-cell action whose track no longer exists is ignored safely after
  coordinator resolution; it never acts on the reused cell's old identity.

## Verification

### Automated

- RED/GREEN tests for preformatted row projections and mutation isolation.
- Native-cell reuse, stable layer/subview identity, stale artwork rejection,
  focus, selection, favorite, menu, drag, and drop behavior.
- All list sources retain a constant page count and avoid full reload on page
  append or one-row mutation.
- Real SwiftData shallow/deep page benchmarks with fixture libraries and every
  supported sort field.
- Cold/warm artwork decode and decoded-byte cache plateau tests.
- Real-window incremental scroll-event benchmark with p50/p95, maximum
  configuration time, host/cell counts, allocations, and reload counters.
- Strict Swift 6 build, focused track-table suites, scoped Cadence tests, and
  the complete `scripts/verify.sh` gate.

### Manual or live

- Physical trackpad scrolling, momentum, rapid reversal, stationary cursor,
  and repeated top-to-bottom/top navigation.
- Minimum, ideal, and wide widths with every column combination.
- Keyboard, VoiceOver, Switch Control, context menu, drag/drop, favorite,
  selection, and current-track updates.
- Instruments SwiftUI, Time Profiler, Hitches, Allocations, Core Animation,
  and Swift Executors traces on the running app.

Automated acceptance cannot prove physical trackpad frame pacing or subjective
smoothness. Those remain explicitly unverified until the live checks run.

## Rollback

The native renderer is introduced behind the existing table coordinator and
can be removed by restoring the SwiftUI hosting-cell factory while keeping the
display projection, bounded sources, paging fixes, and performance tests.
Each migration unit remains local and reviewable in the current diff. No
repository history or user library state is mutated.
