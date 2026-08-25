# Cadence Interface Regression Follow-up Design

**Date:** 2026-08-24
**Status:** Implemented and locally verified; interactive acceptance remains explicit
**Branch:** `qenterra/cadence-interface-regression-followup`

## Purpose

Repair the screenshot-backed interface regressions reported after the interface-coherence change without reintroducing resizable track columns, sidebar motion, technical badges in track rows, or eager loading of unbounded queues.

The work is split into four independently testable units. Shared interaction policies are repaired at their owning boundary instead of duplicating view-local workarounds.

## Acceptance Matrix

| ID | Required behavior |
| --- | --- |
| TRK-01 | An idle non-favorite track row never shows a heart. Exactly the row under the pointer may reveal its empty heart; favorite rows always show a filled white heart. Reuse and scrolling cannot leak hover state to another row. |
| TRK-02 | Favorite changes use an immediate fill/unfill everywhere, without bounce, scale, replacement, or color animation. |
| TRK-03 | Track title and artist form a centered two-line stack. Album, year, and duration align with the title baseline. Fixed columns remain non-resizable and use the available width without displaced text. |
| TRK-04 | Selected track rows use Cadence selection fill with no white outline. Pointer hover uses the quieter Cadence hover fill. |
| TRK-05 | Plain click replaces track selection, Shift selects a range, and either Command or Control toggles one row. A context click on an unselected row selects it first; modified context click extends or toggles the selection before constructing bulk actions. |
| CAT-01 | Albums, artists, and playlists support native multi-selection: a plain click replaces selection and immediately activates the item, Command or Control toggles an item without activation, and Shift selects a contiguous range without activation. |
| CAT-02 | Album and artist sort menus expose sort fields directly, followed by mutually exclusive ascending and descending choices. No nested `Sort X` submenu appears. |
| CAT-03 | Shared row/card buttons do not animate their symbols on press. Home track cards do not show the trailing play triangle. |
| CAT-04 | The Cadence Mode Back control uses the same plain, secondary `chevron.left` label presentation as album, artist, and lyrics-editor Back controls. |
| HOME-01 | Artist cards provide Pin to Home and Unpin from Home context actions. |
| HOME-02 | Home renders separate typed shelves for pinned albums, artists, playlists, and smart collections; unlike kinds are never combined in one Quick Access grid. Empty typed shelves are omitted. |
| PLS-01 | Choosing New Playlist from track actions first presents a native name field. Confirming a non-empty name creates the playlist and adds the captured track IDs through one model-owned flow; Cancel creates nothing. |
| SHELL-01 | Smart Collections can mount its own loading lifecycle and cannot be hidden behind a root loading state that only the hidden page can resolve. Empty and failure states remain reachable. |
| NOW-01 | The Cadence Mode hint remains completely above the player at every supported window height. It may scroll with the context panel when the vertical content cannot fit. |
| NOW-02 | Home and catalog artwork symbols do not bounce or morph when their containing control is clicked. |
| LRC-01 | The lyrics-editor clock reads the playback presentation clock on a stable periodic cadence, uses monospaced digits, and does not derive live time from duration multiplied by a stale progress snapshot. |
| SET-01 | Persistent Boolean controls in Settings use the native macOS switch style rather than checkbox presentation. |

## Unit 1: Native Track Table

### Pointer ownership and favorite visibility

`NativeTrackTableCell` remains the reusable AppKit renderer, but hover is no longer trusted merely because an earlier tracking-area event set a Boolean. The cell gains a pointer reconciliation operation that converts the window pointer location into local coordinates and resolves whether the pointer is inside the current visible bounds. The table coordinator clears hover-only presentation when live scrolling begins and reconciles all visible native cells when scrolling ends or visible bounds change.

Favorite visibility is resolved by a pure presentation policy:

- favorite: always visible, filled, white Cadence accent;
- non-favorite and actual pointer hover: visible, empty, secondary;
- otherwise: hidden, including selected or focused rows;
- live pointer scrolling: hide non-favorite hover affordances.

The AppKit keyframe feedback and SwiftUI symbol replacement/bounce are removed. Optimistic favorite persistence remains: the symbol fills immediately while the request is pending and reverts if persistence fails.

### Geometry and selection chrome

A small row-geometry value type owns the vertical frames used by the native cell. It centers the title/artist stack as a pair and exposes the title-line frame to album, year, and duration. This makes the baseline relationship testable without snapshotting private AppKit internals.

Selection uses only `nativeSelectionFill`. Focus remains represented through accessibility and first-responder state, not a white stroke. Hover uses `nativeHoverFill` only when the row is not selected.

### Context selection

Selection modifier resolution becomes a pure policy accepting explicit modifier flags. Command and Control are both additive toggles. The context-menu callback receives the originating event so the coordinator can update selection before resolving `actionTrackIDs`. Native right-click behavior is preserved: right-clicking an already selected row retains the current group; right-clicking an unselected row without modifiers selects only that row.

## Unit 2: Catalog Selection and Presentation

### Multi-selection model

`CatalogActivationSelection` evolves from one optional target into a scoped ordered selection with a primary target and range anchor. It exposes membership without requiring views to compare against one optional value. Selection is cleared when the catalog destination or media kind changes.

Albums and artists activate on the first unmodified click while replacing the selected set. Command or Control toggles stable IDs and Shift selects a range without activating. Playlist selection updates the detail pane for an unmodified primary selection, while modifier clicks only update the selected set. Shift uses the current sorted visible order.

The selection model does not introduce bulk mutation actions for catalog items in this change. It only supplies native selection behavior and stable visual state.

### Sort control

A shared catalog sort menu presents direct `Button` choices with checkmarks for fields, then a divider, then Ascending and Descending choices. Its label reports the active field and direction. Albums and artists use the same component and retain their existing `AppStorage` keys.

### Motion and accessories

`CadenceRowButtonStyle` keeps immediate pressed opacity but removes `symbolEffect` and animated state interpolation. `HomeMediaTile` makes the trailing accessory optional; track tiles omit it. Destination chevrons may remain where they communicate navigation, but they do not animate.

Cadence Mode uses the established Back control treatment: plain button style, secondary foreground, `chevron.left`, and a descriptive label. The control remains readable over the dark visual field through placement, not a bespoke capsule.

## Unit 3: Home Pins and Playlist Creation

### Typed pin shelves

Home projects pins by `HomePinKind` and emits one `HomeShelf` per non-empty kind:

- Pinned Albums
- Pinned Artists
- Pinned Playlists
- Pinned Smart Collections

Ordering within each kind continues to come from `HomePinStore`. The existing pin revision invalidates the shelves after a context action. Artist tile context menus gain the same pin action already used by albums and artist detail.

### Named playlist transaction

Playlist creation initiated from track actions is represented by a model-owned request containing the captured ordered track IDs and a draft name. A root-level native SwiftUI alert owns the text field so both AppKit and SwiftUI menus can invoke the same flow.

`LibraryStore.createPlaylist` returns the created playlist projection or `nil`. Confirmation trims and validates the name, creates the playlist, and adds the captured tracks using the returned ID rather than reading mutable global selection. Failure keeps the existing library-operation error path; no partially named `Untitled Playlist` is intentionally created. Cancel clears the request without persistence.

## Unit 4: Shell, Now Playing, Lyrics, and Settings

### Smart Collections readiness

The root destination-loading policy never blocks Smart Collections on `isLoadingSmartCollectionData`, because that task is owned by `SmartCollectionsView`. The page mounts immediately and its own list, result, empty, and error regions represent their state. This removes the parent-child loading deadlock while retaining root loading presentation for destinations whose data is loaded independently of their view.

### Vertical Now Playing layout

The standard track-context column becomes vertically scrollable when its content exceeds the workspace height. The artwork keeps the existing height-aware cap; the Cadence Mode hint sits in the normal content stack with enough bottom inset to stay wholly above the player. At normal heights the presentation remains visually unchanged and no scrollbar is forced visible.

### Lyrics editor clock

The clock is rendered inside a periodic `TimelineView` while playing and reads `playbackPresentationTime(atHostUptime:)`. When paused it displays the stable playback state time. Formatting stays `m:ss.SSS` through `LyricTimestampFormatter`, and the text reserves enough intrinsic width to prevent neighboring controls from shifting.

### Settings switches

`ProductionSettingsView` applies native switch toggle style to its subtree. Sidebar visibility, Cadence Mode preferences, and update preferences inherit the style; non-Boolean pickers and buttons are unchanged.

## Error and State Safety

- Pointer reconciliation never mutates track identity or selection.
- Optimistic favorite state remains scoped by item ID and request token so reused views cannot publish another item's result.
- Playlist creation uses captured track IDs and the returned playlist ID, preventing selection races.
- Smart Collection load failures remain surfaced through the existing operation-failure state instead of an eternal spinner.
- Multi-selection stores stable UUIDs and prunes IDs no longer present in the current result.

## Verification Strategy

Every mechanically observable requirement starts with a focused failing test against the current production behavior. Tests exercise pure policies where appropriate and real AppKit cells/coordinators where the failure depends on reuse or context selection.

Focused coverage includes:

- native cell reuse, pointer reconciliation, favorite visibility, row geometry, selection chrome, and context modifiers;
- catalog additive/range selection and activation separation;
- direct sort-menu state, typed Home pin projection, and named playlist transaction;
- Smart Collections destination readiness, Cadence hint bounded layout, presentation-clock formatting, and Settings switch propagation;
- source-level motion checks only where the product contract is specifically the absence of a SwiftUI symbol effect and no runtime semantic hook exists.

Visual acceptance renders temporary, untracked frames for the submitted states: idle and scrolled hearts, minimum/wide track rows, multi-selection, sort menu, Home typed pins, short Now Playing, Cadence Mode Back, lyrics editor timing, and Settings. Tracked baselines are not updated merely to make a broad pixel diff pass.

The final gate is `scripts/verify.sh` from the exact feature worktree. Pointer position, Control/Command context-click behavior, animation feel, and actual text-field focus remain explicit manual checks because automated gates cannot prove them fully.

## Non-goals

- No sidebar icon animation is reintroduced.
- No catalog bulk delete, tagging, or pinning semantics beyond the requested selection behavior.
- No playback engine, library schema, queue, provider, release, signing, or updater redesign.
- No tracked screenshot baseline promotion without separate visual review.
- No commit, push, merge, or release is part of this implementation contract.
