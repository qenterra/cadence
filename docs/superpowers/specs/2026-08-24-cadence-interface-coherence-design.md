# Cadence Interface Coherence Design

## Objective

Make Cadence track lists, catalog grids, navigation, Now Playing, lyrics, and
Cadence Mode feel like one native macOS application. Remove the state leaks,
system-blue styling, unstable geometry, hidden loading work, and inconsistent
input routing reported in the 24 August 2026 acceptance screenshots.

This specification is the source of truth for the approved interface-coherence
workstream. The user's follow-up removes every sidebar icon animation; that
decision supersedes the earlier proposal to retain a lightweight All Tracks
animation.

## Global Constraints

- Remain native macOS 26 or later and Swift 6 with the existing dependency set.
- Keep `NSTableView` as the production track-table virtualization and input
  owner; do not replace it with a custom renderer.
- Preserve stable track IDs, queue order, playback, managed-library safety,
  contextual navigation, accessibility, and Reduce Motion behavior.
- Mount destination chrome immediately. Never add an artificial minimum
  loading delay merely to make a spinner visible.
- Refresh only the active library scope. Pull-to-refresh must not mutate the
  user's files, queue, playback position, tags, or metadata.
- Recreate visual view identity on theme changes without recreating
  `CadenceAppModel`, stopping playback, or resetting navigation state.
- Automated tests use synthetic or in-memory libraries only.
- Do not commit, push, merge, publish, sign, notarize, or mutate external
  systems as part of this workstream.

## Requirement Ledger

### Track lists

- **CUI-01:** Track tables use deterministic, non-user-resizable columns. Album,
  Year, and Time stay stable; Track receives the remaining supported width.
- **CUI-02:** The title label uses every pixel left after artwork and controls;
  it is not capped at a percentage of the Track column.
- **CUI-03:** Codec and synchronized-lyrics pills are absent from every track
  row. The later explicit removal request supersedes the screenshot note asking
  where those pills went.
- **CUI-04:** Selection uses Cadence monochrome surfaces and never the system
  blue selection/focus colors.
- **CUI-05:** Reusing a native row resets transient hover and press state so
  favorite controls cannot appear on unrelated rows while scrolling.
- **CUI-06:** Favorite controls use Cadence primary monochrome styling. Toggling
  a favorite produces a bounded scale/opacity response; Reduce Motion uses the
  non-spatial equivalent.
- **CUI-07:** Artist and album activation hit regions equal their rendered text
  bounds plus normal control padding, never the full column width.
- **CUI-08:** Artist and album text becomes primary on hover and does not flash
  to an unrelated white pressed state on mouse-down.

### Catalog, Favorites, Sidebar, and destination presentation

- **CUI-09:** Album, artist, and playlist artwork cards have a shared fixed
  196-point width. Window changes alter column count, not card size.
- **CUI-10:** Favorites uses one inline segmented Tracks / Albums / Artists
  picker without a nested Type submenu.
- **CUI-11:** Sidebar settings show one flat ordered list. Dragging and
  accessibility Move Up/Down can cross the former navigation groups.
- **CUI-12:** Sidebar destination icons have no activation or replacement
  animation. Selection feedback comes from the row surface and label tone.
- **CUI-13:** Selecting a destination mounts its shell immediately. If its data
  is not ready, it displays an indeterminate native macOS progress state and
  cross-fades to content, respecting Reduce Motion and using no fake delay.
- **CUI-14:** Scrollable library destinations support scoped pull-to-refresh:
  Home, Library/Tracks, Albums, Artists, Favorites, Playlists, Tags, Smart
  Collections, Search, and Trash. SwiftUI scroll pages use `.refreshable`.
  AppKit tables use elastic top-pull tracking with a native
  `NSProgressIndicator`, because AppKit has no `NSRefreshControl` API.
- **CUI-15:** Starting a track from Recently Played moves it to index zero and
  keeps it visible instead of filtering out the current track.

### Now Playing, queue, lyrics, and Cadence Mode

- **CUI-16:** Clicking the Player Bar artwork always opens Now Playing on the
  Lyrics panel. Queue retains its own explicit button.
- **CUI-17:** Now Playing shows the existing audio-format pill and an adjacent
  LRC pill only for synchronized lyrics.
- **CUI-18:** Queue presentation loads current plus at most five Up Next tracks.
  The underlying playback queue stays complete and the five-item window
  advances with the current index.
- **CUI-19:** The Now Playing Cadence Mode hint is a pill button that can request
  activation directly. Active Cadence Mode has a top-left Back pill.
- **CUI-20:** Cadence Mode artwork is capped at 560 points on large canvases and
  has a 0.5-point translucent white border that remains outside the artwork.
- **CUI-21:** Settings expose Enable Cadence Mode, React to Bass, Show
  Synchronized Lyrics, Show Track Information, and Stay in Cadence Mode.
  Disabling the feature deactivates an active session and blocks keyboard and
  pill activation. Disabling bass response preserves keyboard-driven effects.
- **CUI-22:** Shortcuts includes `Z + X` for Cadence Mode.
- **CUI-23:** Now Playing lyrics hide the scroll indicator and use a calm
  0.32-second smooth follow transition. Reduce Motion scrolls without motion.
- **CUI-24:** A new track establishes the lyric scroll position at the top with
  no animation. Automatic active-line following begins on the next line
  transition, so the previous track's middle position never leaks.

### Input and appearance

- **CUI-25:** Escape first cancels active search or tag entry, clears the text,
  and releases focus. Only an Escape with no active text-editing context may
  perform contextual Back/dismiss navigation.
- **CUI-26:** Changing appearance recreates the main and Settings visual
  subtrees, including AppKit representables, while preserving the app model,
  playback, queue, destination, and lifecycle tasks.

## Selected Architecture

### Deterministic track-table geometry and row state

`TrackTableColumnPolicy` becomes the sole width authority. Album, Year, and
Time use stable semantic widths, Track has a supported minimum and receives
remaining width, and unsupported narrow embedded surfaces fall back to the
existing compact column set rather than proportionally crushing every column.
`TrackTableHeaderCell` remains sortable but loses drag state and resizer
semantics. The AppStorage width values leave the production path.

`NativeTrackTableCell` owns an explicit transient-state reset whenever its
represented track identity changes. It lays out the title against the complete
remaining metadata rectangle and omits codec/LRC subviews. Link buttons are
measured from their attributed title plus bounded padding. Hover, selection,
focus, and favorite colors derive from `CadenceTheme`, never
`controlAccentColor`, `selectedContentBackgroundColor`, or
`keyboardFocusIndicatorColor`.

### Fixed catalog cards

Introduce `CatalogCardLayoutMetrics` with `cardWidth = 196` and one helper that
returns `.fixed(cardWidth)` grid items. Albums, artists, playlists, Home,
Favorites, and Search use the helper. Artwork and text keep their current
aspect and line limits; only the number of columns changes.

### Destination phases and refresh

Introduce a small destination-presentation value with loading and ready phases.
The root shell switches selection immediately and uses an opacity replacement
for page content. Existing store availability and per-page loading values stay
authoritative; the host does not create timers.

Introduce `LibraryRefreshScope` and `LibraryStore.refresh(_:)`. Each scope
invalidates and reloads only the active projections using existing repository
and paging operations. The refresh API coalesces concurrent requests and keeps
the last valid content visible on failure. SwiftUI `.refreshable` and the
AppKit elastic-pull coordinator call the same API.

### Cadence Mode preferences and layout

`CadenceModePreferences` owns stable AppStorage keys and a pure
`CadenceModeOptions` value. Root input capture and Now Playing consume the same
options. `CadenceModeSession` gains one direct activation request used by the
pill; the existing two-key state machine remains the keyboard authority.

`CadenceModeLayout` accounts for artwork, optional identity, and optional lyric
slots. The 560-point cap prevents a fullscreen canvas from consuming the
effects field. Disabling bass supplies the identity artwork response while
leaving pulse/key effects active.

### Local input cancellation and theme refresh identity

Search and tag fields own their Escape handling at the focus boundary and
return handled before container-level Back commands. A reusable pure policy
decides whether Escape clears input or falls through, so focus variants share
the same behavior.

Appearance changes increment visual identity below `CadenceRootView`'s
lifecycle boundary and below `CadenceSettingsWindow`'s model ownership. Native
representables are recreated, while root `.task` and `.onDisappear` playback
lifecycle hooks are not retriggered.

## Error and State Handling

- A refresh failure preserves current content and publishes the existing
  operation-failure presentation; it does not blank the destination.
- A destination with resident data skips loading presentation entirely.
- A stale row/artwork/refresh completion is rejected by stable identity and
  library epoch before publication.
- A Cadence Mode preference change while no track exists leaves the session
  inactive and does not navigate.
- LRC status is derived from the accepted document for the current track; stale
  documents cannot badge the next track.
- Escape with an empty, unfocused field is ignored locally so normal contextual
  navigation remains available.

## Verification

### Automated

- RED/GREEN tests for fixed column geometry, disabled resizing, full title
  budget, row-reuse state reset, text-only link frames, monochrome chrome, and
  favorite response state.
- Fixed card-grid metrics and cross-group sidebar reorder tests.
- Recently Played remove/reinsert ordering and epoch rejection tests.
- Scoped refresh, coalescing, stale rejection, and content-preservation tests.
- Destination phase, theme visual identity, and Escape-routing policy tests.
- Queue five-item window and advancing-current-index tests.
- Cadence Mode options, direct activation, disable-while-active, layout cap,
  optional identity/lyrics, bass-response disable, and shortcut tests.
- Lyrics initial-top reset, follow-motion policy, and synchronized LRC badge
  tests.
- Strict Swift 6 focused suites, full test gate, localization, lint, and build.

### Visual and manual

- Render All Tracks at minimum, default, and wide sizes into temporary output;
  inspect title width, link hit areas, selection, hearts, and columns.
- Render fixed-card pages at minimum/default/wide sizes; verify identical card
  bounds and only column-count changes.
- Render Favorites, Sidebar Settings, Now Playing, Lyrics, and fullscreen
  Cadence Mode in dark/light/system appearances.
- Manually verify stationary-pointer scrolling, favorite press feedback,
  text-only album/artist activation, destination loading, refresh gestures,
  theme changes during playback, Escape focus routing, and Cadence Mode Back.
- Automated screenshots do not prove physical trackpad smoothness, audible
  playback, VoiceOver, or installed-app behavior; report those separately.

## Rollback

Each subsystem remains separable: deterministic table policy, fixed cards,
navigation/refresh, and Now Playing/Cadence Mode can be reverted independently.
No user library schema or managed media changes are introduced.
