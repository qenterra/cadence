# Cadence UI System

Cadence uses one adaptive macOS layout system across library browsing,
organization, playback, and settings. The visual goal is calm, compact, and
predictable: Soft Graphite content surfaces, monochrome controls, original
artwork, system typography, and native interaction behavior.

## Product shell

- The window toolbar is an opaque raised graphite surface. It does not expose
  the desktop through a translucent titlebar.
- The navigation rail is 72 points collapsed and 220 points expanded. Icons
  retain the same leading anchor in both states.
- Hover and selection surfaces are clipped to the rail's visible content
  bounds. A collapsed rail never renders an expanded-width row offscreen.
- The workspace always receives the full width and height remaining after the
  rail, divider, toolbar, and player.
- The bottom player remains a separate full-width functional layer and does
  not change page measurements.

## Adaptive workspace contract

Tags, Smart Collections, and Playlists use the same two-pane contract:

- leading pane: resizable from 230 to 420 points;
- trailing pane: fills all remaining width with a practical minimum;
- pane header: 68 points high, 18-point horizontal inset, title2 bold title,
  trailing creation action, and one shared separator;
- list rows: 52 points high, 10-point horizontal list inset, 10-point internal
  inset, and a 6-point continuous corner radius;
- selection: inset from every pane edge and divider; it never overlaps a
  separator;
- detail header: 28-point page inset, large-title hierarchy, secondary
  metadata, and contextual actions;
- empty states: centered inside the body below the header, never centered
  relative to the entire window.

Page-specific behavior remains distinct:

- Tags browse one selected taxonomy item and can explicitly add library tracks.
- Smart Collections expose listening mode first and a separate rule editor.
- Playlists preserve manual order and expose playback actions.

## Tags: adding library tracks

The selected tag's detail header includes `Add Tracks…`. It opens a sheet backed
by the production `LibraryStore`, not preview fixtures.

- The sheet shows the real library in the shared track-table style.
- Search filters title, artist, and album.
- Command-click, Shift-click, and Command-A support multi-selection.
- Tracks already directly assigned to the tag are marked and excluded from the
  pending selection.
- `Add` performs one repository transaction for all selected track UUIDs.
- Inherited assignments remain inherited; the command creates only missing
  direct assignments.
- Success refreshes tag counts and results. Failure keeps the sheet open and
  shows a plain-language error without partial UI state.

## Empty and fixture policy

- The shipping Cadence target contains no synthetic library, tag, playlist,
  smart-collection, favorite, lyric, or import-candidate fixtures.
- Normal and Debug launches always open the production library.
- An empty library renders honest empty states and import actions.
- Deterministic fixtures used by unit tests live only under
  `Tests/CadenceTests`.
- Public screenshots must use an isolated test or UI-test fixture rather than a
  hidden runtime mode in the shipping app.

## App icon

`brand/icon-composer/Cadence.icon` remains the canonical source. XcodeGen sets
the app-icon compiler name and writes both `CFBundleIconFile` and
`CFBundleIconName` as `Cadence`. Verification checks the built application
bundle, not merely the project configuration.

## Typography, spacing, and surfaces

- Large page titles use the system large-title style.
- Pane titles use title2 bold.
- Row titles use body medium only when selected; metadata uses caption or
  callout secondary text.
- Page insets use 28 points, pane headers 18 points, list containers 10 points,
  and compact control gaps 8 points.
- Structural dividers use the shared separator token. Local black dividers and
  ad-hoc opacity values are not allowed.
- Content backgrounds are opaque Soft Graphite. Materials are reserved for
  chrome and popovers.
- Hover feedback is immediate and restrained. Selection does not change row
  geometry. Reduce Motion removes spatial transitions.

## Updated About surface

Cadence follows the current Unspool About pattern:

- one creator/version row;
- a compact two-column link grid below it;
- full-row link targets with subtle hover feedback and an external-link glyph;
- GitHub Profile, Source Code, Wiki, MIT License, Third-Party Notices, and
  Buy Me a Coffee;
- creator attribution remains `Nikita Melnychenko (QenTerra)`;
- the visible version omits the build number.

## Verification

The implementation is complete only after:

1. XcodeGen and SwiftFormat produce no changes.
2. The full Xcode 27 build and unit-test gate passes.
3. Tests cover workspace width allocation, rail geometry, selection insets,
   batch tag assignment, production-empty startup, and app-icon metadata.
4. Wide and minimum-width screenshots are reviewed for All Tracks, Album
   Detail, Tags, Smart Collections, Playlists, and Settings.
5. Keyboard selection, VoiceOver labels, Reduce Motion, System/Light/Dark, and
   tag-assignment error recovery are checked.
