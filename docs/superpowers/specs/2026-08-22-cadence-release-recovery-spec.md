# Cadence Release Recovery Specification

## Objective

Bring the current local Cadence source line to a release-ready state by restoring proven lost behavior, removing the reported visual and motion regressions, eliminating known hot-path churn, and closing the catalog/release safety gaps found during the independent audit.

The source authority is `main@84549bff2d26360ab8dd2fb5a41dc7060754c666`. The three commits on `qenterra/cadence-mode-bass-polish` are evidence and a donor implementation, not a branch to merge wholesale.

## Global constraints

- Platform remains native macOS 26 or later with Swift 6 and the existing dependency set.
- Preserve all storage, recovery, and library-localization work already present on current `main`.
- Do not merge or cherry-pick the divergent bass-polish branch.
- Do not commit, push, tag, sign, notarize, publish, authenticate providers, mutate the real library, or change the default audio application.
- Use deterministic tests and fixture libraries. Never use a screenshot, build result, or passive capture as proof of audible playback or destructive recovery.
- Honor Reduce Motion and Reduce Transparency at every optional motion/material boundary.
- Keep list work proportional to the visible mutation; an unchanged update must not sort, compare, reload, decode, or rebuild visible rows unnecessarily.
- Release artifacts must be bound to an exact clean source revision.

## Acceptance requirements

### R-01 Navigation animation ownership

A sidebar activation has exactly one symbol-effect owner. Press state must not add a second forward/reverse bounce. The 48-point hit target is preserved while the visual selection surface is inset and adjacent rows remain visibly separate.

### R-02 Browser selection chrome

Shared browser rows do not draw the leading selected capsule or a selected outline. Album, artist, playlist, and navigation selections must not introduce a white/accent line at the leading edge.

### R-03 Track row geometry

Track hover and selection chrome is horizontally inset from the table cell. Content and hit testing retain the existing full-row behavior.

### R-04 Track header chrome

Track/Album/Year/Time resize boundaries remain interactive but are transparent while idle. A separator may appear only while the matching resize target is hovered or dragged.

### R-05 Lyric boundary scheduling and motion

Synchronized lyrics update at lyric boundaries or a modest bounded clock, never an always-on 120 Hz SwiftUI observer. The clock pauses with playback and when the view is inactive. One active-line change produces one stable line transition and one scroll command; Reduce Motion removes both optional animations.

### R-06 Cadence Mode bass response

PCM playback supplies a realtime-safe low-frequency level; Native playback supplies a precomputed envelope fallback. Coordinator state resets across track, seek, pause, gapless successor, and route changes. Cadence Mode artwork uses a bounded, smoothed scale response, is identity at silence/pause/Reduce Motion, and does not allocate or cross the main actor from the audio tap.

### R-07 Settings Liquid Glass

The Settings top strip draws one native Liquid Glass surface in normal runtime and one deterministic opaque surface only in screenshot mode or Reduce Transparency. All tabs use one stable layout subtree and retain identical icon/text bounds while selection changes.

### R-08 List update proportionality

Nonvirtual tables compute sorted rows once per input/sort change. An unchanged SwiftUI update performs no row reload. Selection reloads only the old and new selected rows. A one-row data mutation reloads only that row when identity/order are stable. Hosting cells keep stable root identity where possible.

### R-09 Artwork budget

Track rows request the `trackRow` asset variant and decoded pixel dimensions are bounded near their rendered backing-scale requirement. Cache and decode tasks are not restarted by unrelated selection/hover updates.

### R-10 Accessibility motion and actions

Favorite actions remain reachable by keyboard and accessibility when the pointer is not hovering. Optional row/favorite/tile animations honor Reduce Motion.

### R-11 Native and visual verification

Every primary destination, transient workspace, nested album/artist/playlist detail, all seven Settings tabs, empty/loading/error states, collapsed navigation, light/dark appearances, and minimum/ideal/wide layouts receive fixture-based native rendering coverage. Live Computer Use is supplementary and may be marked unavailable if ScreenCaptureKit cannot capture the app.

### R-12 Managed-library mutation serialization

Import, relocation, and full reset share one mutation lease. Move/reset reject or await active import work, cancellation is joined, SQLite/search handles close before package replacement, and no old operation can publish into a newly attached library.

### R-13 Atomic local-catalog migration

The main SQLite file and sidecars migrate into a temporary snapshot with a durable phase record. The snapshot is validated, then atomically promoted. Restart after any copy boundary retries or rolls back; final-file existence alone never means migration succeeded.

### R-14 Durable full-reset recovery

Full reset writes a durable phase manifest before moving the active package. Startup deterministically completes or rolls back every interruption point and never silently treats a stranded backup as an empty library.

### R-15 Durable Trash restore

Restore records intent and phase before moving files. Restart after any file move or database save converges idempotently to fully restored or fully trashed state.

### R-16 Library attachment epochs

Every repository attachment increments an epoch. Snapshot/search/refresh tasks publish only when their captured epoch remains current; lifecycle-owned work is cancelled and joined, and the lyrics index is explicitly closed before detachment.

### R-17 Import and bulk-operation consistency

Import recovery validates and rolls back artwork as well as audio and lyrics. Bulk Trash either rolls back atomically or reports a partial result and always refreshes visible state. One unreadable metadata-repair candidate cannot fail an otherwise healthy library.

### R-18 Release provenance

Archive creation and reuse require a clean tagged HEAD, embed the exact Git SHA, and bind verification attestation to that SHA. A same-version archive from another commit fails before signing or publication. Hosted CI must not claim the Xcode gate passed when it was skipped.

### R-19 Remote lifecycle and cache integrity

Remote media arrives progressively with bounded memory. Latest connect/restore/disconnect intent wins; deactivation cancels and joins in-flight downloads. Failed connection leaves no credentials or active source. Cached objects are hash-verified before reuse.

### R-20 Large-library bounded work

Smart Collection summaries share one candidate snapshot; search debounces and cancels stale queries; artist-credit backfill avoids full-catalog fetch after completion; tag pagination is bounded; lyric sidecar matching uses a pre-index; same-parent bookmark activation balances every security-scope acquisition.

## Verification boundary

Automated gates can prove compilation, deterministic behavior, fixture rendering, packaging contracts, concurrency order, and interruption recovery. They cannot prove audible output, output-device routing, bass feel on the user's music, VoiceOver quality, or real hardware frame pacing. Those remain explicit manual acceptance items unless directly exercised in the running app.
