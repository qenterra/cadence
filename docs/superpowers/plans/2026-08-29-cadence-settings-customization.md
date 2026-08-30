# Cadence Settings Customization Implementation Plan

> Execute inline in the current dirty worktree. Preserve all pre-existing edits;
> do not commit, push, release, or mutate the music library.

**Goal:** Add the requested customization and maintenance controls through a
typed preference layer, shared UI policies, and PlaybackCoordinator-owned
behavior, while reorganizing Settings into coherent native macOS categories.

**Architecture:** A centralized preference registry defines portable and
session-only keys. SwiftUI views bind to typed raw values, shared layout/table
policies consume them, and playback collaborators receive an injectable
preference source. Settings import/export/reset is an explicit allowlisted JSON
service. Queue persistence is a separate private session store.

**Technology:** Swift 6, SwiftUI, AppKit, AVFoundation, MediaPlayer,
UserDefaults, Swift Testing, existing Cadence screenshot harness.

---

### Task 1: Typed preference registry and portable profile service

**Files:**
- Create or extend `Sources/Cadence/App/CadencePreferences.swift`
- Create or extend `Sources/Cadence/Features/Settings/SettingsDataController.swift`
- Test in `Tests/CadenceTests/CadencePreferencesTests.swift`
- Update `Cadence.xcodeproj/project.pbxproj` if required

1. Write failing tests for defaults, invalid-value repair, the portable key
   allowlist, reset exclusions, schema rejection, and all-or-nothing import.
2. Run the focused test target and confirm RED.
3. Implement typed enums, key registry/default registration, versioned Codable
   snapshot, validation, atomic apply, and customization-only reset.
4. Run focused tests to GREEN.

### Task 2: Shared visual preferences

**Files:**
- Modify `Sources/Cadence/DesignSystem/CadenceLayout.swift`
- Modify all `CatalogCardLayoutMetrics` consumers
- Modify shared native track-table files under
  `Sources/Cadence/Features/Library/`
- Modify Now Playing lyrics presentation
- Add focused semantic/layout tests

1. Add failing tests for each card-size range and conditional artwork geometry.
2. Parameterize the shared media-card grid policy and bind all catalog surfaces
   to one stored size.
3. Thread `showsArtwork` through the single native track table; reclaim the
   artwork slot when disabled.
4. Apply semantic lyrics size roles and elapsed/remaining time formatting.
5. Run focused tests and affected screenshot smoke checks.

### Task 3: Home and navigation customization

**Files:**
- Modify `ProductionHomeView.swift` and Home support
- Modify `SettingsSidebarCard.swift`
- Add a Home/Navigation Settings card
- Modify navigation configuration only through its public normalization helpers
- Add focused tests

1. Add failing tests for fixed Recently Played, configurable remaining order,
   visibility, corrupt-state repair, and sidebar reset.
2. Implement normalized Home section storage and ordered rendering.
3. Add native checkbox/reorder rows and Sidebar reset.
4. Run focused tests.

### Task 4: Playback policies and private queue session

**Files:**
- Modify `PlaybackCoordinator` extensions and backend request models
- Modify `SystemMediaSession`
- Add queue-session persistence collaborator
- Wire production factory/model lifecycle
- Add focused coordinator/backend/session tests

1. Add failing tests for Previous behavior, seek interval/clamping, ReplayGain
   calculation, route-recovery policy, and queue snapshot validation/restoration.
2. Inject a preference source into PlaybackCoordinator.
3. Implement Previous and seek policies plus remote-command intervals.
4. Apply ReplayGain safely in PCM and native backends without modifying the user
   volume value.
5. Persist stable managed queue snapshots and restore them paused on launch;
   exclude external-file queues and missing identities safely.
6. Gate automatic route resume without overriding manual pause.
7. Run the full PlaybackCoordinator focused suite.

### Task 5: Settings UI normalization and utilities

**Files:**
- Modify `ProductionSettingsView.swift`, `SettingsTabStrip.swift`, and cards
- Modify managed library and remote cache collaborators
- Add utility/controller tests

1. Add the Playback category and rename Sidebar to Navigation.
2. Build native Settings rows for every new preference and move Cadence Mode.
3. Add Reveal in Finder, Clear Cache, Reset Sidebar, Home configuration, and
   Settings import/export/reset with honest scope/error copy.
4. Ensure cache clearing is derived-data-only and Finder/open-save operations
   remain injectable or separately bounded for tests.
5. Run focused Settings, library, and remote-cache tests.

### Task 6: Localization, screenshots, and complete verification

**Files:**
- Modify `Sources/Cadence/Resources/Localizable.xcstrings`
- Update affected documentation screenshots only through the repository harness
- Check all touched Swift/project files

1. Regenerate/update localization through the repository-supported flow.
2. Run formatter/static/project consistency checks.
3. Run focused suites with fresh output.
4. Run `bash scripts/verify.sh` under `caffeinate -d -i` with pinned
   `DEVELOPER_DIR` and `CADENCE_IMAGE_PYTHON`.
5. Inspect the final diff for scope and unrelated-change preservation.
6. Checkpoint and close the Noetic workstream only after objective evidence is
   fresh; report manual QA boundaries separately.
