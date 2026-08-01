# Onboarding and In-App Guide

## Purpose

Cadence should explain its local-library model and core workflows without
requiring sample media, changing the library, or forcing a long tutorial on
first launch. The experience consists of a short welcome flow, an optional
guided tour, and focused chapters that remain available from the Help menu.

## Product principles

- Keep the user in control. The welcome flow offers `Start Tour` and
  `Explore on My Own`.
- Explain the real interface. Guide steps point to production views and honest
  empty states instead of synthetic tracks or collections.
- Never perform library actions. The guide may navigate, but it does not import,
  play, edit, delete, or create content.
- Stay useful after first launch. Every chapter can be replayed from
  `Help > Cadence Guide`.
- Follow the current Cadence theme, accessibility settings, and reduced-motion
  preference.

## First-launch welcome

The welcome flow appears after the library session finishes opening. It is a
centered sheet sized for the default macOS window and remains usable at the
minimum supported window size.

The flow contains three concise pages:

1. **Welcome to Cadence** introduces the local music player.
2. **Your music stays yours** explains that imports preserve originals and that
   managed media lives in `~/Music/Cadence.library`.
3. **Make the library your own** introduces tags, Smart Collections, playlists,
   artwork, and line-timed lyrics.

The final page offers two actions:

- `Start Tour` completes the welcome flow and opens the Essentials tour.
- `Explore on My Own` completes the welcome flow and returns to the current
  application state.

Closing or quitting before either action does not mark onboarding as complete.
The welcome flow is shown once per onboarding version, not once per app build.

## Essentials tour

The default tour contains nine short steps:

1. Sidebar and section navigation
2. Library browsing
3. All Tracks and configurable columns
4. Import Music and Finder drag and drop
5. Player Bar and playback controls
6. Now Playing and the queue
7. Lyrics and Lyrics Editor
8. Tags, Smart Collections, and playlists
9. Settings, customization, and Help

Each guide card shows a title, no more than two short explanatory paragraphs,
`Back`, `Next`, `Skip Tour`, and progress such as `4 of 9`. `Done` replaces
`Next` on the final step.

Advancing a step may use the existing application navigation request to reveal
the relevant destination. It must not select media, open a file picker, start
playback, or mutate persisted state.

## Focused chapters

`Help > Cadence Guide` opens a chapter picker with:

- Library & Import
- Playback & Lyrics
- Tags & Collections
- Playlists
- Settings & Customization

The picker also offers the complete Essentials tour. Chapters reuse the same
step model and presentation as the first-run tour. Starting a chapter always
begins at its first step; partial progress is not restored after relaunch.

## Presentation

The welcome sheet uses Cadence surfaces, system typography, the app icon, and
the fixed monochrome accent. It adapts to System, Light, and Dark appearances.

During a guide step:

- the target receives a restrained light border and soft glow;
- the rest of the Cadence content is dimmed without tinting the desktop or
  changing the application palette;
- one guide card is placed near the target without covering it;
- the card is repositioned when the window changes size;
- only opacity and a short positional transition are animated;
- Reduce Motion replaces positional movement with a crossfade.

The overlay must stay within the Cadence content window. It does not draw over
unrelated applications, create stacked popovers, or permanently alter layout.

## Architecture

### Guide model

`GuideChapter` owns an ordered collection of `GuideStep` values. A step defines:

- stable identifier;
- title and message;
- target `GuideAnchor`;
- optional navigation destination or playback workspace;
- preferred card placement;
- fallback presentation when the target is unavailable.

### Coordinator

An observable `GuideCoordinator` is the single source of truth for welcome and
guide presentation. It owns the active chapter, current step, completion state,
and commands for back, next, skip, finish, and replay.

The coordinator uses existing navigation APIs. It does not duplicate library,
playback, or destination state.

### Anchors and overlay

Views opt in with a small guide-anchor modifier. Anchor frames are collected in
the root view's coordinate space and rendered by one `CadenceGuideOverlay`.
Feature views do not own guide sequencing or persistence.

If an anchor is absent, the overlay presents the step as a centered information
card. For example, Lyrics explains that line-timed content appears after a
track with lyrics is selected. A missing anchor never blocks progression.

### Persistence

Only durable onboarding completion is stored in `UserDefaults` under a
versioned key. Active step and partial chapter progress remain in memory.
Resetting or replaying the guide does not change unrelated preferences.

## Input and accessibility

- `Escape` closes the current guide after the same non-destructive semantics as
  `Skip Tour`.
- Left and right arrow keys move between available steps.
- Return activates `Next` or `Done`.
- Guide controls have explicit accessibility labels and logical focus order.
- VoiceOver announces the step title, text, and progress when a step changes.
- The highlighted target is not required for understanding the card.
- Increased contrast and reduced transparency use more opaque surfaces and a
  defined border.

## Error and lifecycle behavior

- Welcome presentation waits until the library is no longer recovering.
- A failed or unavailable library still permits the welcome flow and Help guide;
  affected steps use their informational fallback.
- Closing a guide restores normal interaction without changing the user's
  current library data.
- Starting a new chapter replaces the current guide instead of stacking another
  presentation.
- A guide version change may show the welcome flow once again only when the
  onboarding content or core navigation changes materially.

## Verification

Implementation is complete after:

- unit tests cover chapter ordering, step navigation, completion persistence,
  replay, and unavailable-anchor fallback;
- navigation tests confirm that guide steps use existing destinations without
  mutating library state;
- UI smoke tests cover first launch, opting out, the Essentials tour, and Help
  chapter replay;
- SwiftFormat, SwiftLint, build, and the complete `scripts/verify.sh` gate pass;
- the live interface is reviewed in Dark, Light, minimum window size, and
  Reduce Motion configurations.
