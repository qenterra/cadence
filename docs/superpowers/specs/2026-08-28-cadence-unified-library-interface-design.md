# Cadence Unified Library Interface Design

**Date:** 2026-08-28
**Status:** Approved for implementation; interactive acceptance remains explicit
**Checkout:** current clean `main` working tree

## Purpose

Repair the submitted screenshot-backed interface regressions while making the
native track table, application commands, appearance propagation, settings
controls, and adaptive catalog layout own their behavior at one shared
boundary. The change must not duplicate per-screen track-row implementations
or describe automated checks as visual acceptance.

## Acceptance Matrix

| ID | Required behavior |
| --- | --- |
| TRK-01 | The title and artist form one compact two-line stack centered in the row. Album, Year, and Time use one centered single-line frame and the same AppKit text renderer/baseline behavior. |
| TRK-02 | All production track contexts use the same `ProductionTrackList` surface and native cell engine: All Tracks, album, artist, playlist, smart collection, favorites, search, tags, and library browser results. |
| TRK-03 | A stationary pointer keeps the correct row hover highlight while the list is scrolled. Reuse cannot leave hover on a different row. |
| TRK-04 | The active playing track uses a three-bar animated playback indicator over artwork. Paused/hovered tracks use the play affordance. Reduce Motion presents static bars. |
| TRK-05 | Artist Favorite Tracks and All Tracks expand into the artist page and use the page scroll view instead of nested track-table scrolling. |
| KEY-01 | Unmodified Space toggles playback anywhere in the main window when a playable item exists, without producing the macOS rejection sound. Text editing, menus, sheets, modal UI, and local Space controls keep the key. |
| APP-01 | Light, Dark, and System appearance changes do not reconstruct the root content hierarchy or recursively invalidate every subview. System removes the application override so titlebar and frame follow macOS. |
| SET-01 | Persistent switches are compact native macOS switches aligned at the trailing edge of full-width setting rows. |
| SET-02 | Navigation visibility uses checkboxes before destination icons. Home can be dragged or moved with accessibility actions like every other destination. |
| SET-03 | About uses the application icon, product/version/build identity, short local-music description, author line, and one grouped link list for source, wiki, license, and notices. |
| LAY-01 | Album, artist, Home, Favorites, Search, and artist-release grids add columns and distribute the full available width instead of fixing cards at 196 points. |
| LAY-02 | The lower player gives metadata more width at normal and wide windows; title truncation starts only after the adaptive metadata allocation is exhausted. |
| HOME-01 | Recently Played is the first Home shelf after the page header. |
| ACT-01 | Confirmation/primary completion actions use system blue; destructive actions use system red and retain semantic roles and labels. Neutral/cancel actions remain neutral. |

## Architecture

### One production track-list surface

`ProductionTrackList` is the only feature-facing track-list component. It
forwards both materialized projections and `LibraryTrackWindow` virtual data
to the existing `ProductionTrackTable`/`TrackTableCore` engine. Its
`TrackListScrollOwnership` policy has two values:

- `contained`: the table owns vertical scrolling and expands to its parent;
- `page`: the containing page owns vertical scrolling, the table height is
  `headerHeight + rowHeight * rowCount`, and the internal scroller is disabled.

`ProductionTrackTable` and `TrackTableCore` stay implementation boundaries.
Existing paging, fixed columns, selection, queue, drag/drop, artwork loading,
and targeted reload behavior remain unchanged.

Artist Favorite Tracks and All Tracks use `.page`. Full destinations use
`.contained`. This solves the nested artist scroll without replacing the
virtualized AppKit row implementation.

### Native row geometry and interaction

`NativeTrackRowGeometry` owns two independent vertical frames:

- a compact two-line frame centered around the row midpoint;
- a single-line frame centered directly on the row midpoint.

Clickable artist and album metadata use a lightweight `NSTextField`-based
control instead of `NSButtonCell` title drawing. Title, artist, album, year,
and time therefore share text-field metrics; hit targets, keyboard activation,
tooltips, accessibility link roles, and navigation callbacks remain intact.

Live-scroll presentation disables expensive implicit animation but does not
erase hover. Every bounds change reconciles the pointer against visible cells,
so the cell currently under a stationary pointer becomes hovered as content
moves beneath it.

`NativePlaybackIndicatorView` owns three rounded white bar layers. Only the
visible active playing row runs staggered repeating Core Animation keyframes.
Reuse, pause, removal, and teardown remove animations. Reduce Motion displays
the same three bars without animation. The overlay is mouse-transparent so the
artwork play action remains available.

### Window-level playback command capture

`AppPlaybackKeyboardCapture` installs one local AppKit event monitor scoped to
the window that hosts it. `AppPlaybackKeyDecision` accepts only a non-repeating,
unmodified Space key-down when `AppCommandFocus` is not blocking. The capture
derives focus from the actual first responder and current modal/menu/sheet
state, then routes `.togglePlayback` through `AppCommandRouter`.

The event is consumed only when the router handles it. Otherwise it is passed
through so import review, tap-to-sync, text entry, controls, and system behavior
are not stolen.

### Appearance ownership

`AppearanceController` sets only `NSApplication.appearance`. Explicit Light or
Dark assigns the corresponding AppKit appearance; System assigns `nil`.
Per-window appearance overrides, descendant window traversal, recursive view
invalidation, and appearance-derived `.id(...)` reconstruction are removed.
SwiftUI and native cells update through `effectiveAppearance` propagation.

### Settings and About

`SettingsSwitchRow` is a full-width HStack with label content, a spacer, and a
labels-hidden `.switch` toggle using `.small` control size. The navigation card
overrides its visibility control to `.checkbox`, placing the checkbox before
the destination icon and label.

Navigation order decoding preserves the first occurrence of every saved
destination, including Home, then appends missing destinations. Moving is one
generic remove/insert operation with no Home exception.

About uses the real application icon from `NSApplication`, a compact hero
identity block, and one bordered grouped list of external links. Version and
build come from the bundle through `SettingsAboutMetadata` so missing preview
values have deterministic fallbacks.

### Adaptive catalog and player layout

Catalog grids use an adaptive minimum card width and no fixed maximum. Tiles
fill the grid column offered by SwiftUI. At wider sizes SwiftUI adds columns;
the remaining width is distributed evenly rather than becoming a dead strip
on the right.

`PlayerBarRegionLayout` deterministically allocates a fixed output region, a
bounded metadata region, and the remaining width to transport/progress. The
metadata region grows from 244 points toward 420 points before text is
truncated. Metadata text receives higher layout priority than its trailing
favorite/add control.

### Semantic action color

`CadenceActionTone` maps `.confirmation` to system blue and `.destructive` to
system red. Prominent completion buttons apply confirmation tone. Destructive
buttons keep `ButtonRole.destructive` and use the destructive tone where they
render as ordinary buttons. Color supplements text, symbols, and roles; it is
never the only meaning.

## State and Error Safety

- Keyboard capture never consumes Space when no command was handled.
- Track cells continue routing actions by represented stable track ID.
- Embedded table height clamps invalid counts to zero and cannot become
  negative or non-finite.
- Navigation decoding removes duplicates and unknown destinations without
  losing a valid saved Home position.
- Appearance changes preserve navigation, selection, scroll, playback, and
  pending-edit state because no root identity changes.
- Playback indicator animations stop on reuse and teardown.

## Verification

Every mechanically observable change begins with a focused failing Swift
Testing/AppKit test and follows RED → GREEN → REFACTOR. Coverage includes:

- row geometry and real rendered text frames;
- live-scroll pointer reconciliation and reuse;
- playback-indicator visibility, animation, and Reduce Motion;
- shared list source/scroll ownership and artist embedded height;
- window-scoped Space routing and blocked responder cases;
- application-only appearance overrides;
- Home reorder persistence and settings layout policies;
- adaptive grid and player width calculations;
- Home section order and action-tone resolution.

After focused suites pass, regenerate the Xcode project if a new source file
requires it, run `scripts/verify.sh`, inspect the final diff, and perform a
bounded native walkthrough against the submitted states. Physical pointer
hover, titlebar/frame appearance, drag feel, animation feel, and exact visual
alignment remain manual acceptance evidence, not automated proof.

## Non-goals

- No playback engine, queue, library schema, persistence, provider, updater,
  signing, notarisation, release, or remote-service redesign.
- No tracked screenshot baseline promotion merely to make a diff green.
- No commit, push, merge, or branch cleanup.
- No replacement of the existing native AppKit table virtualization or paging.
