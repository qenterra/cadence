# Cadence Catalog Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make import, relocation, reset, migration, restore, and repository attachment crash-safe and generation-safe.

**Architecture:** Introduce one library-mutation lease and explicit lifecycle epochs. Persist phase manifests before cross-file operations, perform work in staging locations, validate complete snapshots, and atomically promote or deterministically recover on startup.

**Tech Stack:** Swift 6, SwiftData, SQLite sidecars, Foundation file coordination, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-08-22-cadence-release-recovery-spec.md`

## Global Constraints

- Preserve actual configured managed-folder identity; never hard-code `Music`.
- No real-library mutation during verification; use temporary fixture packages and fault injection.
- Every destructive multi-step operation must be restart-idempotent and recovery-tested at every phase.
- Do not commit, push, tag, sign, publish, or authenticate providers.

---

### Task 1: Shared library mutation lease

**Files:**
- Create: `Sources/Cadence/ManagedLibrary/LibraryMutationCoordinator.swift`
- Modify: `Sources/Cadence/Import/ImportCoordinator.swift`
- Modify: `Sources/Cadence/App/CadenceAppModel+LibraryLocation.swift`
- Modify: `Sources/Cadence/App/CadenceAppModel+LibraryReset.swift`
- Modify: `Sources/Cadence/Features/Settings/ManagedLibrarySettingsCard.swift`
- Test: `Tests/CadenceTests/LibraryMutationCoordinatorTests.swift`

**Interfaces:**
- Produces: an async exclusive mutation lease with operation kind, cancellation/join, and observable busy state.

- [ ] Add continuation-controlled failing tests for import/copy, import/commit, move, and reset overlaps.
- [ ] Implement one coordinator shared by import, move, and reset; define latest legal behavior explicitly as reject or await.
- [ ] Make cancellation join the owned import task and keep committing work non-cancellable only while the lease remains held.
- [ ] Disable conflicting Settings actions from the same state and test it.
- [ ] Run concurrency tests under strict Swift 6 checking.

### Task 2: Atomic local catalog migration

**Files:**
- Modify: `Sources/Cadence/Persistence/LocalLibraryCatalog.swift`
- Modify: `Sources/Cadence/Persistence/LibraryContainerFactory.swift`
- Test: `Tests/CadenceTests/LocalLibraryCatalogMigrationTests.swift`

**Interfaces:**
- Produces: a staged snapshot and durable migration manifest with copying, validating, and promoted phases.

- [ ] Add fault injection after main, WAL, SHM, validation, and promotion; prove current destination-exists shortcut fails restart recovery.
- [ ] Copy into a unique staging directory, fsync/close inputs, validate SQLite, persist phase, then atomically rename into the final catalog.
- [ ] On startup, inspect the manifest/staging snapshot and retry or roll back; never accept main-file existence alone.
- [ ] Run all migration and storage-location tests.

### Task 3: Durable full reset

**Files:**
- Modify: `Sources/Cadence/ManagedLibrary/ManagedLibraryResetter.swift`
- Modify: `Sources/Cadence/Persistence/LibrarySession.swift`
- Test: `Tests/CadenceTests/LibraryResetRecoveryTests.swift`

**Interfaces:**
- Produces: a reset manifest with prepared, backupMoved, stagedPromoted, identityCommitted, and cleanupComplete phases.

- [ ] Add kill/restart fault tests at every move, validation, identity commit, and cleanup boundary.
- [ ] Persist and fsync the reset phase before each irreversible transition.
- [ ] Recover on startup before empty-library detection, choosing deterministic complete-or-rollback behavior.
- [ ] Validate package identity/catalog consistency before deleting the backup.
- [ ] Run reset, relocation, and recovery suites.

### Task 4: Durable Trash restore and bulk consistency

**Files:**
- Modify: `Sources/Cadence/Persistence/LibraryRepository+TrashRestore.swift`
- Modify: `Sources/Cadence/Persistence/LibraryRepository+TrashRecovery.swift`
- Modify: `Sources/Cadence/Persistence/LibraryRepository+Trash.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore+Trash.swift`
- Test: `Tests/CadenceTests/LibraryTrashRecoveryTests.swift`

**Interfaces:**
- Produces: a restore operation phase record and explicit partial/atomic bulk result.

- [ ] Add interruption tests after each restored file and before/after database save.
- [ ] Persist restore intent/phase before file moves and make startup finish or undo idempotently.
- [ ] Define bulk Trash as atomic where possible; otherwise return exact completed/failed IDs and always refresh Store state in `defer`.
- [ ] Run Trash, undo/redo, and restart recovery suites.

### Task 5: Attachment epochs and lifecycle closure

**Files:**
- Modify: `Sources/Cadence/Persistence/LibraryStore+Lifecycle.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore.swift`
- Modify: `Sources/Cadence/Persistence/LibrarySession.swift`
- Modify: `Sources/Cadence/Search/LyricsSearchIndexer.swift`
- Test: `Tests/CadenceTests/LibraryStoreLifecycleEpochTests.swift`

**Interfaces:**
- Produces: monotonically increasing `libraryEpoch`, guarded publication, owned task cancellation/join, and explicit index close.

- [ ] Add A/B continuation tests where old A finishes after new B and assert B remains authoritative.
- [ ] Increment epoch on attach/detach and capture/check it around every lifecycle-owned suspension.
- [ ] Cancel/join owned snapshot/search work and call `LyricsSearchIndexer.close()` before repository/package replacement.
- [ ] Run lifecycle, relocation, reset, and search tests.

### Task 6: Import assets and tolerant metadata repair

**Files:**
- Modify: `Sources/Cadence/Import/ManagedLibraryImportRecovery.swift`
- Modify: `Sources/Cadence/Persistence/ManagedMetadataRepairService.swift`
- Modify: `Sources/Cadence/App/CadenceAppModel+MetadataRepair.swift`
- Test: import recovery and metadata repair test suites.

**Interfaces:**
- Produces: artwork-inclusive import ownership validation and per-item repair failures.

- [ ] Add failure/corruption tests after artwork promotion and before catalog commit.
- [ ] Validate, hash, and roll back artwork with audio/lyrics under the same manifest ownership.
- [ ] Convert metadata repair to per-item results so one unreadable track remains reportable/retryable without failing the session.
- [ ] Run import recovery, metadata repair, startup, and library readiness tests.

### Task 7: Full safety gate and adversarial recovery review

**Files:**
- Modify only defects found by review.

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: deterministic recovery across every injected interruption phase.

- [ ] Run all persistence/import/managed-library tests plus the full suite.
- [ ] Dispatch a fresh adversarial reviewer focused on crash windows, reentrancy, identity, and rollback ownership.
- [ ] Fix every Critical/Important finding and repeat targeted/full gates.
- [ ] Verify all tests use temporary packages and no real library path was touched.
