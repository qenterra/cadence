# Cadence Production Remediation Design

## Status

Approved for implementation on 2026-08-01.

This design covers the current production remediation pass and completion of
the existing onboarding work. Product additions such as Library Health,
Folder Watch, Command Palette, listening history, Smart Queue, tag presets,
metadata bundles, and listening sessions are explicitly deferred.

## Goals

- Keep catalog browsing, sorting, tags, queues, and Smart Collections correct
  when the library contains more than one 200-record repository page.
- Make production playback, queue editing, navigation, recovery, and keyboard
  interaction honest and actionable.
- Bound memory used by artwork and Smart Collection data.
- Separate recoverable feature failures from fatal library availability.
- Finish and commit the approved first-run welcome and replayable Help guide.
- Remove production runtime forks that select obsolete preview interfaces.
- Preserve the existing managed-library package, UUID identities, playback
  snapshots, import contract, and current SwiftData schema.
- Deliver the work as independently verifiable atomic commits.

## Non-goals

- No cloud service, telemetry, online metadata lookup, streaming catalog, or
  Graph feature.
- No mutation of imported source audio or source lyrics.
- No new rating persistence or SwiftData migration in this pass.
- No arbitrary per-device audio routing until both playback backends can
  support it consistently.
- No new product features from the separate capability backlog.
- No screenshot refresh before the production interface is final.

## Delivery strategy

Use a staged compatibility approach. First isolate the existing onboarding
work, then repair production data contracts, then update the UX, and only then
remove obsolete runtime preview forks. This keeps every commit buildable and
avoids combining a broad model rewrite with correctness fixes.

Independent implementation blocks may be developed in parallel when their
file ownership does not overlap. Commits are integrated sequentially on the
current branch because all agents share one Git index and worktree.

## Existing worktree boundary

The worktree already contains the first-run guide implementation and related
layout anchors. Those changes must be verified and committed before remediation
changes touch the same shell, player, library, or Now Playing files.

The onboarding commit includes only:

- `Sources/Cadence/Features/Guide/`;
- guide anchors in existing production views;
- guide coordinator wiring in the app shell;
- guide tests and documentation;
- generated project synchronization required by `project.yml`.

Unrelated working-tree changes must not be staged accidentally.

## Catalog query and paging architecture

### Query contract

Production track paging is described by one query value containing:

- scope: all tracks, artist, album, or tag;
- normalized search text;
- repository-backed sort field and direction.

The repository owns sorting and page boundaries. A SwiftUI table may request a
new sort descriptor, but it must not globally sort only the projections already
loaded into memory.

Keyset cursors are used for stable scalar fields where the schema supports
them. Relationship-backed sorts may initially use a bounded offset cursor if
SwiftData cannot express a stable relationship keyset without denormalized
schema fields. Any offset query is reset after a catalog mutation.

### Store state

Every paged production resource owns:

- the active query;
- the next cursor;
- an `isLoadingNext` guard;
- a request generation;
- loading and recoverable error state.

After an asynchronous request completes, the store verifies that its captured
generation and query are still current. Appends are deduplicated by UUID. A
search, sort, scope change, or relevant mutation increments the generation and
replaces the current page.

### Relationship browsing

The Library browser must not derive selected-artist albums or selected-album
tracks by filtering the globally loaded pages.

A production browser store owns separate state for:

- the global artist page;
- albums for the selected artist;
- tracks for the selected album;
- independent cursors, generations, loading states, and failures.

Album and Artist detail screens use the same scoped repository APIs. They do
not silently stop after 200 related records.

### Verification

Fixtures cover 205 and 401 records, duplicate sort keys, ascending and
descending sorts, concurrent load-next calls, stale search responses, and
relationships whose records occur only after the first global page.

## Playback queue architecture

The playback queue remains a stable ordered snapshot of track UUIDs. Its UI
projection must not depend on the current catalog page.

The repository provides an ordered batch projection API:

1. fetch requested UUIDs in bounded chunks;
2. build a projection dictionary;
3. return projections in the exact input order;
4. represent unresolved UUIDs explicitly as unavailable rows instead of
   silently removing them from the visible queue.

The production queue view model refreshes when the ordered UUID snapshot
changes. It preserves history and the current item while allowing selection,
reordering, removal, and clearing only in Up Next.

Queue edits register one understandable Undo operation using the prior
`PlaybackQueueState`; Redo restores the edited state. Undo and reorder must not
change the current track, playback position, canonical album order, saved
playlist, or Smart Collection rule.

## Tags

Tags receive the same cursor, loading guard, generation, and stale-response
protection as other catalog resources. Refresh replaces the first page and
publishes its next cursor; it does not make tags after record 200 unreachable.

Effective tagged-track queries use bounded batch fetches rather than one fetch
per direct assignment. Album inheritance and track exclusions retain their
current semantics:

`direct union inherited minus excluded inherited assignments`.

Large UUID predicates and batch mutations are chunked to stay below SQLite
variable limits. The tag track picker searches and pages instead of loading
the complete track catalog.

## Smart Collections

`LibraryStore` must not retain a second full array of track projections for
Smart Collections.

The repository exposes:

- compact distinct rule options for tags, artists, albums, years, and formats;
- evaluation of a saved or draft rule to ordered track UUIDs;
- paged projection of result UUIDs for display;
- the complete ordered UUID snapshot for Play and Shuffle.

Rule leaves produce UUID sets. `All` intersects, `Any` unions, and `Not`
subtracts from the current live track-ID universe. Tag leaves preserve exact,
descendant, inherited, and excluded semantics.

The existing Rating condition is hidden in production because `TrackRecord`
does not persist a rating. Adding rating storage requires a separate schema
design and migration rather than comparing every production track with zero.

Performance fixtures measure rule evaluation and tag queries with 10,000 and
50,000 synthetic records. The pass records measured time and memory rather
than declaring an arbitrary performance claim.

## Artwork memory and recovery

### Memory

Raw artwork assets use a bounded cache keyed by artwork UUID and revision.
Cache cost is the stored byte count and both count and total-cost limits are
set. Changed artwork invalidates only its own entries. Concurrent requests for
the same revision share one in-flight load.

The decoded image cache also receives a total-cost limit based on decoded pixel
size, not only a count limit.

### Crash recovery

Artwork edits use a versioned manifest under
`Staging/ArtworkEdits/<operation UUID>/` with states:

`prepared -> fileInstalled -> metadataCommitted -> cleanup`.

The manifest records the owner, mutation kind, new artwork identity and hash,
and previous artwork paths. The service stages and validates bytes, installs on
the same volume, applies an idempotent SwiftData mutation, then removes old
files and the manifest. Launch recovery completes or rolls back incomplete
operations before the library is published as ready. Invalid paths, hashes,
or symlinks are quarantined without deleting user data.

## Error model and recovery UX

`LibraryAvailability` is reserved for startup, package recovery, and initial
catalog failures. Playlist, tag, search, Smart Collection, artwork, and other
feature operations publish a typed recoverable operation failure without
clearing previously valid projections.

Rules:

- failed mutations do not increment revisions or reload dependent data;
- failed reads preserve the last successful data instead of replacing it with
  an empty array;
- errors identify the operation and expose dismissal or retry;
- one local operation failure must not replace the entire app with the fatal
  library screen.

Fatal library failures provide Retry, contextual Reveal in Finder actions, and
disclosed technical details. The canonical library remains
`~/Music/Cadence.library`; the UI does not offer a misleading arbitrary Locate
Library action.

Playback failures remain visible and provide bounded Retry and Skip actions.
No automatic infinite retry or skip loop is introduced.

## Player and Audio Output UX

When there is no current playback item:

- Play, Previous, Next, Shuffle, Repeat, seek, and Queue are disabled;
- the player distinguishes an empty library from a ready library with no
  selected track;
- import or track-selection guidance is shown without synthetic content.

Volume and output information remain available. Audio Output displays the
current route, playback path status, and `Open Sound Settings...`. It does not
pretend Cadence can route both PCM and native playback to an arbitrary device
until that capability exists and has been tested on real hardware.

## Track table interaction

Production track tables accept a shared selection binding.

- Single click selects.
- Double click and Return start playback.
- Up and Down move focus and selection without starting playback.
- Artist and Album links navigate without triggering the row action.
- Selection uses the existing neutral `BrowserRowSurface`.
- Column resizers show a persistent restrained line, strengthen on hover and
  drag, and expose accessibility increment and decrement actions.

Selection is stored by UUID and pruned when a new query removes a row.

## Production Queue UX

The panel visibly separates History, Now Playing, and Up Next. Only Up Next can
be selected or edited.

- Click, Command-click, and Shift-range manage selection.
- Delete removes the selected Up Next rows.
- Dragging a selection uses a neutral opaque preview and white insertion line.
- Clear, Remove, and Reorder support Undo and Redo.
- Current track and history are never deleted by these actions.
- An unavailable UUID remains visible with a non-playing unavailable state.

## Navigation, layout, and search

Production Now Playing exposes a visible contextual Back control. Back and
Escape restore the originating destination while retaining the current track
and selected Lyrics or Queue panel.

The 1080-point minimum window remains supported. Library widths use an adaptive
compact tier instead of manufacturing a 950-point content width after the
expanded sidebar is subtracted. Secondary metadata compresses before the
Artist, Album, and Track hierarchy becomes unusable.

For new installations at the default wide window, the sidebar begins expanded.
An existing stored preference is never overwritten. The expansion button has
dynamic accessibility labels.

Grouped search returns an explicit `hasMore` or total for each result group.
Headers disclose truncation and provide a paged See All destination. Search
generation guards prevent an older query from replacing newer results.

## Onboarding integration

The approved guide remains non-destructive:

- it may navigate using existing application APIs;
- it never imports, plays, edits, deletes, or creates data;
- missing production anchors use an informational fallback;
- closing welcome before either explicit choice does not complete onboarding;
- Help chapters remain replayable.

Guide cards accommodate measured content height or bounded scrolling instead
of assuming a fixed height. Output copy describes the honest route/status UX.

Automated tests cover coordinator state, persistence, navigation, geometry,
fallbacks, and representative rendering. Live acceptance still covers first
run with empty and real libraries, Dark and Light appearances, minimum window,
Reduce Motion, Reduce Transparency, Increased Contrast, keyboard navigation,
and VoiceOver announcements.

## Production-only runtime and dead-code cleanup

Once production behavior is complete, shipping views no longer branch on
`LibrarySession.preview` to select an alternative interface. Library, Albums,
Artists, Tags, Now Playing, and Player Bar render production paths directly.

Preview fixtures remain available to tests where they still express domain
behavior. Candidate source trees are deleted only after a symbol-level
reference search proves their sole runtime entry was an obsolete preview fork.
Names containing `Preview` are not deleted mechanically: several are current
production projections or test fixtures.

Debug and Release builds must both succeed after cleanup. Documentation must
not advertise a `--public-preview` runtime argument unless an implementation
exists; screenshot fixtures belong to a test-only production-backed harness.

## Screenshot delivery

Screenshots are regenerated last from a temporary production SwiftData and
managed-library fixture containing synthetic public data. The harness fixes
window size, appearance, locale, and scale. It must not access the developer's
real library.

Library, Now Playing, Tags, and Settings screenshots are checked for current UI
parity, privacy, raster dimensions, and README rendering.

## Commit sequence

1. `feat(onboarding): add first-run guide and Help chapters`
2. `refactor(catalog): introduce query-aware paging`
3. `fix(library): page relationships and global sorting`
4. `fix(playback): resolve complete queue projections`
5. `feat(queue): add production selection and undo`
6. `fix(tags): page taxonomy and batch queries`
7. `refactor(smart-collections): remove full track cache`
8. `perf(artwork): bound artwork caches`
9. `fix(persistence): surface recoverable operation failures`
10. `fix(artwork): add crash-recoverable edit manifests`
11. `fix(player): make playback and output states actionable`
12. `feat(library): add keyboard selection and adaptive layout`
13. `feat(search): disclose and page bounded results`
14. `refactor(app): remove runtime preview forks and dead views`
15. `docs(ui): align architecture and production screenshots`

Tests normally travel in the commit that introduces the behavior. A separate
test-only commit is used only when it proves an invariant spanning multiple
prior commits.

## Verification gates

Each commit receives focused tests and a Debug build before integration. The
final current-tree gate is:

1. inspect status, unstaged diff, and staged diff;
2. regenerate `Cadence.xcodeproj` from `project.yml` using XcodeGen;
3. run SwiftFormat lint and SwiftLint;
4. run the complete unit and rendering suite through `scripts/verify.sh`;
5. run an arm64 Release build without signing;
6. run `git diff --check` and repository privacy/path checks;
7. inspect the final commit sequence and confirm no unrelated work was staged;
8. perform the documented live UX and listening gates where the environment
   permits them, reporting every unverified manual gap explicitly.

Large-library tests must include paging, concurrent load-next, stale responses,
ordered queue projection, tag inheritance and exclusions, Smart Collection
facets and rule semantics, cache eviction, and recoverable operation failures.

## Acceptance criteria

- A 401-track fixture remains correctly ordered and navigable across pages.
- An artist or album whose children are absent from the first global page shows
  its complete scoped results.
- A 401-item queue renders in snapshot order independently of catalog paging.
- More than 200 tags remain discoverable and editable.
- Smart Collection options and results include records after the first page
  without retaining a second full projection cache.
- Artwork caches evict by cost and artwork edits recover from every manifest
  state without losing the prior valid cover.
- Feature-operation failures preserve previously valid UI data and do not mark
  the entire library unavailable.
- Empty playback, output route, table selection, queue editing, Back, compact
  layout, and bounded search have explicit accessible behavior.
- Shipping views use production UI paths; confirmed obsolete preview trees are
  removed while necessary test fixtures remain.
- Onboarding remains non-destructive, replayable, accessible, and honest in an
  empty library.
- The full verification gate passes, and remaining hardware, listening,
  VoiceOver, or visual checks are named rather than implied.
