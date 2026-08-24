# Cadence Shell, Refresh, and Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Make destination changes respond immediately, add scoped native
pull-to-refresh, make Escape respect active text entry, and fully refresh
visual identity when appearance changes without disrupting playback.

**Architecture:** Separate the root visual subtree from its model/lifecycle
owner. Reuse current per-page/store loading truth in a destination host, add a
typed refresh scope over existing repository reload primitives, and resolve
Escape at the local focus boundary before container navigation.

**Tech Stack:** Swift 6, SwiftUI, AppKit elastic scrolling with
`NSProgressIndicator`, Observation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-08-24-cadence-interface-coherence-design.md`

## Global Constraints

- Implement CUI-13, CUI-14, CUI-25, and CUI-26 exactly as specified.
- Never add a fake loading timer or blank resident data during refresh.
- Refresh is read-only with respect to managed media and user metadata.
- Theme refresh must not call `shutdownPlayback` or recreate
  `CadenceAppModel`.
- Follow RED -> GREEN -> REFACTOR and do not commit or push.

---

### Task 1: Destination presentation phases

**Files:**

- Create: `Sources/Cadence/Features/Shell/DestinationPresentation.swift`
- Create: `Tests/CadenceTests/DestinationPresentationTests.swift`
- Modify: `Sources/Cadence/Features/Shell/CadenceRootView.swift`
- Modify: destination pages only where they currently hide their shell while
  loading.

**Interfaces:**

- Produces: `DestinationPresentation.resolve(hasResidentContent:isLoading:)`
  returning `.content` or `.loading`.
- Produces: `CadenceDestinationHost` that mounts the selected page immediately
  and replaces only its data region.

- [x] **Step 1: Add failing pure tests:** loading with no resident content is
  `.loading`; loading with resident content is `.content`; ready is `.content`.
- [x] **Step 2: Add a failing root-host test proving selection changes the
  destination identity synchronously without waiting for an async task.**
- [x] **Step 3: Implement the pure policy and root host using native
  indeterminate `ProgressView`; transition with opacity only and disable motion
  under Reduce Motion.**
- [x] **Step 4: Remove page branches that keep the previous destination visible
  until a load completes. Keep existing error/empty states.**
- [x] **Step 5: Run destination, root-navigation, and accessibility tests.**

### Task 2: Scoped refresh contract

**Files:**

- Create: `Sources/Cadence/Persistence/LibraryRefreshScope.swift`
- Create: `Sources/Cadence/Persistence/LibraryStore+Refresh.swift`
- Create: `Tests/CadenceTests/LibraryStoreRefreshTests.swift`
- Modify: existing store lifecycle/paging extensions only to expose the
  smallest reload operations needed by the scope dispatcher.

**Interfaces:**

- Produces: `enum LibraryRefreshScope: Hashable, Sendable` with home, library,
  allTracks, albums, artists, favorites, playlists, tags, smartCollections,
  search, and trash cases.
- Produces: `@MainActor func refresh(_ scope: LibraryRefreshScope) async`.

- [x] **Step 1: Add a failing dispatcher test for each scope using real in-memory
  repository/store fixtures. Assert only the matching content clocks or
  projections change.**
- [x] **Step 2: Add failing concurrency tests proving duplicate same-scope
  refreshes coalesce and a stale library epoch cannot publish.**
- [x] **Step 3: Add a failing failure test proving resident content remains and
  the operation-failure surface receives the error.**
- [x] **Step 4: Implement the scope enum, in-flight scope set/generation, and
  dispatcher by composing current load/reload methods. Do not rescan files or
  replace the playback queue.**
- [x] **Step 5: Run refresh, epoch, paging, and operation-failure tests.**

### Task 3: SwiftUI and AppKit pull-to-refresh adapters

**Files:**

- Modify: `Sources/Cadence/Components/CadencePageScrollView.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCoordinator.swift`
- Modify: `Sources/Cadence/Features/Library/TrackTableCore.swift`
- Modify: Home, Library/Tracks, Albums, Artists, Favorites, Playlists, Tags,
  Smart Collections, Search, and Trash page entry views.
- Create: `Tests/CadenceTests/RefreshPresentationTests.swift`

**Interfaces:**

- Produces: optional async `refreshAction` on `CadencePageScrollView`.
- Produces: `TrackTablePullRefreshPolicy` plus one retained native progress
  indicator that awaits the same store refresh action. AppKit does not provide
  the iOS-only `NSRefreshControl` API.

- [x] **Step 1: Add failing adapter tests proving one user gesture invokes one
  action and keeps the control refreshing until the async action completes.**
- [x] **Step 2: Add failing page-routing tests mapping every approved
  destination to its literal refresh scope.**
- [x] **Step 3: Implement `.refreshable` on SwiftUI pages and one retained
  elastic-pull progress indicator on AppKit scroll views; make updates
  idempotent across representable refreshes.**
- [x] **Step 4: Wire each destination to `store.refresh(scope)` and run refresh,
  page, and table representable tests.**

### Task 4: Local Escape cancellation policy

**Files:**

- Create: `Sources/Cadence/Components/TextEntryEscapePolicy.swift`
- Create: `Tests/CadenceTests/TextEntryEscapePolicyTests.swift`
- Modify: `Sources/Cadence/Features/Shell/CadenceSearchModifier.swift`
- Modify: `Sources/Cadence/Features/NowPlaying/ProductionNowPlayingView+Metadata.swift`
- Modify: `Sources/Cadence/Features/Tags/ProductionTagEditorInspector.swift`
- Modify: `Sources/Cadence/Features/Tags/ProductionTagsView.swift`
- Modify: relevant container `.onExitCommand` handlers.

**Interfaces:**

- Produces: `TextEntryEscapePolicy.resolve(isFocused:textIsEmpty:)` returning
  `.cancelEntry` or `.propagate`.

- [x] **Step 1: Add failing table tests:** focused non-empty, focused empty, and
  presented search all cancel locally; unfocused empty propagates.
- [x] **Step 2: Add failing focus-routing tests proving a local cancellation
  clears the bound text, sets focus nil, and does not call the Back closure.**
- [x] **Step 3: Implement the policy and focused-field handlers. Search Escape
  clears query/dismisses search; tag Escape clears drafts and releases focus.**
- [x] **Step 4: Make root/container Escape act only when the local policy
  propagates. Run search, tag, Now Playing, and contextual-navigation tests.**

### Task 5: Theme visual subtree refresh

**Files:**

- Create: `Sources/Cadence/App/AppearanceRefreshIdentity.swift`
- Create: `Tests/CadenceTests/AppearanceRefreshIdentityTests.swift`
- Modify: `Sources/Cadence/CadenceApp.swift`
- Modify: `Sources/Cadence/Features/Shell/CadenceRootView.swift`
- Modify: `Sources/Cadence/App/AppearanceController.swift`

**Interfaces:**

- Produces: `AppearanceRefreshIdentity` derived from exact appearance raw value
  and a monotonic visual revision.
- Produces: root/settings visual hosts keyed below model/lifecycle ownership.

- [x] **Step 1: Add failing identity tests proving dark -> light changes visual
  identity while repeated dark does not.**
- [x] **Step 2: Add a failing lifecycle test proving a visual refresh does not
  recreate the app model, call playback shutdown, change queue/destination, or
  reset the Cadence Mode session object.**
- [x] **Step 3: Key the inner main-window and Settings visual hosts by the
  appearance identity. Keep `.task`, app delegate connection, media-session
  activation, and shutdown hooks outside the keyed subtree.**
- [x] **Step 4: Retain `AppearanceController` window appearance application and
  remove redundant recursive refresh work only if the new representable
  identity makes it unnecessary in tests.**
- [x] **Step 5: Run appearance, lifecycle, playback, Settings, and native-table
  recreation tests.**

### Task 6: Shell verification checkpoint

**Files:**

- Modify: `docs/verification/2026-08-24-interface-coherence.md`

- [x] Run destination, refresh, epoch, Escape, theme, root lifecycle, and
  accessibility focused tests.
- [x] Run SwiftFormat/SwiftLint for touched files.
- [x] Exercise temporary light/dark/system captures and record manual checks
  for refresh gesture feel, immediate selection response, and theme switching
  during audible playback.
