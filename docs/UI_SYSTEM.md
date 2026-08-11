# Cadence UI System

Cadence uses one adaptive macOS layout system across library browsing,
organization, playback, and settings. The visual goal is calm, compact, and
predictable: Soft Graphite content surfaces, monochrome controls, original
artwork, system typography, and native interaction behavior.

Shared semantic colors, radii, and feedback motion come from the local
QenTerra Design System Swift package. `CadenceTheme` is the product facade:
it maps QDS 1.11 semantic values into adaptive AppKit/SwiftUI colors while
Cadence keeps ownership of music-specific geometry, artwork, playback, and
lyrics. `qds-consumer.json` and `qds-exceptions.json` are validated by the
read-only consumer doctor during `scripts/verify.sh`.

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
- `scripts/update_screenshots.sh` is the only supported capture entry point; it
  enables an opt-in test that renders the production root against in-memory
  SwiftData and synthetic public metadata.

## App icon

`icon/Cadence.icon` remains the canonical source. XcodeGen sets
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

## Welcome and in-app guide

- First launch presents three short pages after the library session opens.
- Completion is recorded only after `Start Tour` or `Explore on My Own`; simply
  dismissing the sheet does not silently opt the user out.
- Guide steps reuse production navigation and anchor preferences. They may
  reveal a destination, but never import, play, edit, delete, or create data.
- Missing targets use a centered explanatory card, so an empty library cannot
  trap the user in the tour.
- Keyboard navigation, accessibility focus, increased contrast, reduced
  transparency, and Reduce Motion are supported by the same overlay.

The detailed behavior and lifecycle contract lives in
[`ONBOARDING_GUIDE.md`](ONBOARDING_GUIDE.md).

## Now Playing Cadence Mode

- Standard Now Playing always shows the quiet `Z + X — Cadence Mode` hint.
  Physical `Z` and `X` positions are recognized regardless of the active
  keyboard layout, but neither key produces a pulse, particle, or haptic while
  the standard view is visible. Editing controls, sheets, menus, and other
  workspaces retain their normal keyboard behavior.
- Pressing opposite lanes within 180 ms enters Cadence Mode. Activation itself
  is visually clean and does not emit an effect; subsequent `Z` and `X` hits
  produce the left and right effects. The artwork uses one continuous hero
  transition from the context column to the horizontal center, while standard
  Now Playing fades and softens. `Escape`, a track change, or leaving Now
  Playing exits immediately; otherwise every accepted hit restarts a
  ten-second inactivity deadline.
- Cadence Mode presents a five-line viewport beneath the artwork and smoothly
  centers the active synchronized line. It reuses the production Now Playing
  lyric treatment: 24 pt semibold typography, an opaque primary active line,
  and the same inactive opacity and soft blur. Lyrics never use shimmer,
  animated color, or accent glow. Blank rows are omitted. Missing, partial,
  and unsynchronized lyrics show an honest track/status fallback and never
  invent an active line.
- Shared feedback uses QDS motion through `CadenceTheme`. The longer Cadence
  Mode entry and exit are named product motions because the artwork hero
  transition has no second QDS consumer; they remain interruptible and reduce
  to the QDS dismiss transition when Reduce Motion is enabled.
- Behind the active composition, one conic artwork-color field rotates while a
  radial bloom travels across the workspace. Their soft native gradient
  falloff provides the blurred appearance without a live blur filter. Both are
  Core Animation layers driven by compositor transforms beneath a dark static
  scrim. Cadence Mode deliberately uses dark foreground semantics in both
  system appearances so lyrics and effects keep reliable contrast.
- Each lane owns one active trio of color fields plus one bounded outgoing trio.
  Repeating the same key crossfades the outgoing wash instead of cutting it;
  `Z` and `X` overlap independently. Releasing a key never truncates the effect.
- Accent colors are sampled from the current artwork. Grayscale artwork keeps
  an artwork-faithful neutral palette with lifted midtones, so effects remain
  visible without inventing hue. Missing, transparent, or unreadable artwork
  uses a restrained deterministic Cadence palette instead of disabling the
  mode.
- Every hit starts all three fields at the corresponding artwork edge and sends
  them outward across the complete Now Playing workspace underneath track
  context, Lyrics or Queue, and structural dividers. Only the outer workspace
  bounds clip the expanding flash; the right panel attenuates it smoothly for
  text readability.
- Active effects use artwork-colored gradient textures over the dark artwork
  background; there is no white activation flash or generic gray backdrop.
- Color fields follow the approved HTML impact timing: a 1.1-second
  `cubic-bezier(.1, .76, .14, 1)` lifecycle, scale from 0.2 to 1.48, and an
  opacity peak at the eased 10% point. Washes use pre-rendered 160 px radial
  textures with no live gradient or blur pass, so Core Animation only moves,
  scales, and fades cached content without invalidating SwiftUI on every frame.
- Every hit emits 4–5 artwork-colored hybrid particles from the corresponding
  side of the artwork. Z launches left and X launches right in broad outward
  fans with randomized angle, delay, velocity, drag, gravity, size, lifetime,
  and opacity. The effect budget is capped at 16 particle layers. Their paths
  are sampled once when the key is accepted, then a reusable Core Animation
  layer pool advances the shard-to-dust motion on the compositor. Releasing a
  key or pressing the other lane never truncates pending particles.
- Reduce Motion stops background drift, replaces expansion with a static color
  pulse, changes Cadence Mode through a short crossfade, and suppresses
  traveling particles. Reduce Transparency makes the background base opaque,
  removes pulse blur, and keeps solid particle geometry. Increased Contrast
  strengthens the background scrim.
- Background, washes, and particles are compositor-driven. No Cadence Mode
  surface uses a live Gaussian blur or a per-frame SwiftUI timeline. Exactly
  two persistent layers provide background motion; transient fields and
  particles use fixed reusable layer pools. Active hits do not play synchronous
  haptics because frame pacing takes priority. Cadence Mode lyrics update
  independently at 10 Hz.
- The minimum performance contract is stable 60 FPS on an Apple M1 and stable
  120 FPS on an Apple M1 Pro connected to a 120 Hz display, without sustained
  frame drops during background motion or rapid alternating `Z`/`X` input.
  Hardware acceptance runs through `scripts/verify_cadence_frame_pacing.sh`;
  it requires at least 99.5% of the display target, no active-mode regression
  beyond 0.5% of baseline, and no interval longer than 1.5 frame budgets.
  Builds, model tests, and screenshots do not satisfy this gate.

## Verification

The implementation is complete only after:

1. XcodeGen and SwiftFormat produce no changes.
2. The QDS consumer doctor passes with only exact documented exceptions.
3. The full Xcode 27 build and unit-test gate passes.
4. Tests cover workspace width allocation, rail geometry, selection insets,
   batch tag assignment, production-empty startup, and app-icon metadata.
5. Wide and minimum-width screenshots in Light and Dark appearances are
   reviewed for All Tracks, Album Detail, Tags, Smart Collections, Playlists,
   Settings, standard Now Playing with its hint, and active Cadence Mode over
   Lyrics, including the grayscale palette.
6. Keyboard selection, VoiceOver labels, Reduce Motion, System/Light/Dark, and
   tag-assignment error recovery are checked.
7. Cadence Mode frame pacing is profiled on baseline M1 and M1 Pro hardware at
   their 60 Hz and 120 Hz targets; a build or screenshot gate alone does not
   satisfy this hardware acceptance.
