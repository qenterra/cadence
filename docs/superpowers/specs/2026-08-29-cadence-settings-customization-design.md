# Cadence Settings Customization Expansion

Date: 2026-08-29
Status: approved for implementation by the user's “Делай сразу до конца” request

## Outcome

Cadence gains a coherent, native-macOS Settings surface for visual density,
Home organization, playback behavior, library utilities, cache maintenance,
and portable preferences. The feature uses one typed preference vocabulary and
one set of shared presentation policies so the same option behaves consistently
across every relevant surface.

## Information Architecture

The Settings toolbar contains eight categories:

1. General — default audio application, appearance, notifications, and settings
   data actions.
2. Playback — queue restoration, Previous behavior, seek interval, playback
   time display, ReplayGain normalization, output-recovery resume, lyrics text
   size, and Cadence Mode.
3. Library — managed-library status, reveal in Finder, relocation, and deletion.
4. Navigation — Home section order/visibility plus sidebar order/visibility and
   reset.
5. Remote Media — provider status, cache budget, and cache clearing.
6. Shortcuts — the existing reference page.
7. Updates — the existing update policy.
8. About — the existing Cadence-styled About page.

Settings use native pickers, checkboxes, switches, confirmation dialogs, open
and save panels, and trailing controls. Destructive or potentially surprising
actions describe their scope before confirmation.

## Preference Domain

A centralized preference registry owns keys and defaults. Behavior variants use
typed, raw-representable enums rather than boolean combinations:

- Catalog card size: Automatic, Small, Medium, Large.
- Playback time: Elapsed or Remaining.
- Previous: Restart Current After Three Seconds or Always Previous.
- Seek interval: 5, 10, 15, or 30 seconds.
- Volume normalization: Off or Track ReplayGain.
- Lyrics text size: Small, Standard, or Large.

Additional toggles cover track-table artwork, queue restoration, and resuming
playback after a recoverable audio-route interruption.

Defaults preserve existing behavior: automatic cards, artwork shown, elapsed
time, restart-current Previous behavior, 15-second seek, normalization off,
standard lyrics, queue restoration enabled, and route recovery enabled.

## Visual Customization

Card size applies to media/catalog cards everywhere the shared card layout is
used: albums, artists, Home shelves, search, favorites, and artist releases.
It does not scale Settings groups, alerts, player controls, or track rows.
Automatic retains the responsive 164–196 point range. Small, Medium, and Large
select progressively wider responsive ranges while still filling useful width.

Track artwork is controlled in the shared native track table. When disabled,
the artwork view is hidden and title/artist content moves into the reclaimed
space; no invisible artwork spacer remains. Every consumer of the shared table
inherits the same behavior.

Lyrics size changes semantic text roles in the Now Playing lyrics reader while
preserving Dynamic Type and accessibility behavior.

## Home and Sidebar

Recently Played remains the first Home section and cannot be hidden or moved,
matching the existing product requirement. Pinned Items and Favorites can be
shown, hidden, and reordered. Corrupt or incomplete stored values are repaired
against the canonical section set.

Sidebar reset restores the canonical destination order and visibility. Home
remains movable in the sidebar configuration; reset is a reversible preference
operation and never changes library content.

## Playback Behavior

Queue restoration persists a private session snapshot containing only stable
track identifiers, queue source, order/current item, shuffle/repeat state, and
position. It is not part of settings export. Relaunch restoration resolves
available managed tracks and restores paused, never surprise-autoplays.

Previous behavior is evaluated by PlaybackCoordinator. In restart-current mode,
pressing Previous after three seconds seeks to zero; otherwise it moves to the
previous queue item. Always Previous skips this restart rule.

The seek interval drives app seek actions and macOS remote-command preferred
intervals. Seeks clamp to the current track duration.

Track ReplayGain normalization computes a safe linear gain from the existing
track gain metadata and caps it by the stored peak when available. It is applied
inside both playback backends independently of the user's volume. Missing or
invalid metadata resolves to unity gain. Album normalization is not offered
because Cadence does not currently store album ReplayGain.

Route recovery honors the auto-resume preference only when playback was active
before a recoverable output transition. Manual pause remains authoritative.

## Utilities and Portable Settings

Reveal Library uses Finder and is disabled when no managed-library location is
available.

Clear Cache removes derived remote-media cache content only. It preserves the
managed library, local source media, remote connection configuration, and
credentials. The UI reports completion or a recoverable error.

Export writes versioned JSON using an explicit allowlist of user-facing,
portable preferences. Import validates the entire document before atomically
applying supported values. Reset removes all Cadence customization keys and
re-registers defaults without touching:

- the managed library or its location;
- queue/session state;
- remote-provider configuration and credentials;
- notification authorization;
- update state and app/window runtime state.

The UI states these exclusions before import/export/reset. Unknown future keys
are ignored only when the schema version remains supported; malformed values or
unsupported schemas reject the whole import.

## Verification Boundaries

Automated coverage verifies preference defaults and repair, export/import
allowlisting and atomicity, layout ranges, track-row geometry, Home ordering,
playback decisions, ReplayGain math, queue snapshot validation, and cache scope.
The generated Xcode project and localization catalog must remain valid, affected
Settings and primary-page screenshots must regenerate, and the full repository
gate must pass with pinned Xcode and image Python.

Audible loudness equivalence, physical output reconnection behavior, Finder
activation, and installed-app open/save panels remain explicit live/manual QA
boundaries rather than claims inferred from unit tests.
