# Cadence Release, Remote, and Large-Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind releases to exact source and bound remote and large-library work by cancellation, integrity, and dataset size.

**Architecture:** Carry explicit generation tokens through remote operations, stream bytes progressively into cancellable cache tasks, verify content hashes at the point of use, and replace repeated full-catalog work with indexed or shared snapshots. Stamp every archive with source provenance and enforce it before signing.

**Tech Stack:** Swift 6, URLSession async bytes, CryptoKit, SwiftData/SQLite, shell release scripts, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-22-cadence-release-recovery-spec.md`

## Global Constraints

- No provider authentication or real remote mutation in verification.
- No signing, notarization, publishing, tag creation, or remote push.
- Tests use fake transports, temporary caches, and synthetic catalogs.
- Do not commit changes.

---

### Task 1: Release provenance contract

**Files:**
- Modify: `scripts/prepare_release.sh`
- Modify: `scripts/verify.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `docs/UPDATES.md`
- Test: `Tests/ReleaseContractTests/*`

**Interfaces:**
- Produces: embedded Git SHA, clean/tagged-head checks, and SHA-bound reuse attestation.

- [ ] Add shell-contract tests proving a same-version archive from another SHA and a dirty/untagged source fail before signing.
- [ ] Stamp archive metadata with the exact clean HEAD and verify it during new and reused archive paths.
- [ ] Couple release preparation to a recorded full-gate attestation for that SHA.
- [ ] Make hosted CI state explicitly that Xcode gates are unavailable rather than reporting an incomplete green release gate.
- [ ] Run release contract tests without signing or network publication.

### Task 2: Remote intent generations and credential rollback

**Files:**
- Modify: `Sources/Cadence/Remote/RemoteLibraryController.swift`
- Modify: `Sources/Cadence/Remote/WebDAV/WebDAVAuthentication.swift`
- Modify: `Sources/Cadence/Remote/GoogleDrive/GoogleDriveAuthentication.swift`
- Modify: `Sources/Cadence/App/CadenceAppModel+Factory.swift`
- Test: remote controller/authentication tests.

**Interfaces:**
- Produces: latest-intent generation and transactional credential activation.

- [ ] Add continuation-controlled A/B connect, restore/disconnect, failed-connect, and cleanup-failure tests.
- [ ] Capture and verify a generation around every suspension; old operations cannot publish after a newer intent.
- [ ] Persist credentials only after provider validation/activation succeeds, or roll them back on every failure.
- [ ] Make disconnect deactivate in `defer` even when cleanup fails.
- [ ] Run all remote lifecycle tests.

### Task 3: Progressive cancellable remote cache

**Files:**
- Modify: `Sources/Cadence/Remote/WebDAV/WebDAVProvider.swift`
- Modify: `Sources/Cadence/Remote/GoogleDrive/GoogleDriveProvider.swift`
- Modify: `Sources/Cadence/Remote/RemotePlaybackSource.swift`
- Modify: `Sources/Cadence/Remote/RemoteMediaCache.swift`
- Test: provider/cache tests.

**Interfaces:**
- Produces: progressive byte stream, cache cancellation/join, and SHA-256 validation before reuse.

- [ ] Add a slow multi-gigabyte fake response test that observes first chunk before completion and bounded buffered bytes.
- [ ] Stream URLSession bytes into staging files rather than materializing complete `Data`.
- [ ] Couple materialization/prefetch tasks to caller and cache lifecycle; deactivate cancels and joins them before releasing the provider.
- [ ] Re-hash cached objects before returning playable URLs; same-size corruption must redownload or fail.
- [ ] Run provider, cache, cancellation, and integrity tests.

### Task 4: Bounded Smart Collections and search

**Files:**
- Modify: `Sources/Cadence/Persistence/LibraryRepository+SmartCollections.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore+SmartCollections.swift`
- Modify: `Sources/Cadence/Features/SmartCollections/SmartCollectionsView.swift`
- Modify: `Sources/Cadence/Features/Shell/CadenceRootView+Bindings.swift`
- Modify: `Sources/Cadence/Persistence/LibraryStore+LyricsSearch.swift`
- Test: smart collection and search performance/lifecycle suites.

**Interfaces:**
- Produces: one immutable candidate snapshot per refresh and one debounced cancellable search task.

- [ ] Instrument and fail tests when twenty rules fetch a 50k catalog more than once per refresh.
- [ ] Share candidate data across summary/result evaluation or move eligible predicates into the database.
- [ ] Own one debounced search task, cancel superseded persistence/FTS work, and suppress stale failure publication.
- [ ] Run rule correctness plus performance and rapid-typing tests.

### Task 5: Bounded startup, tag paging, and sidecar matching

**Files:**
- Modify: `Sources/Cadence/Persistence/LibraryContainerFactory.swift`
- Modify: `Sources/Cadence/Persistence/LibraryRepository+Catalog.swift`
- Modify: `Sources/Cadence/Import/ImportInspectionService.swift`
- Modify: `Sources/Cadence/Import/LyricsMatcher.swift`
- Modify: `Sources/Cadence/ManagedLibrary/LibraryLocationController.swift`
- Test: migration, tag paging, import performance, and location-controller suites.

**Interfaces:**
- Produces: durable artist-credit migration marker, bounded tag query, indexed sidecar matcher, and balanced security scope.

- [ ] Add large-fixture counters proving already-backfilled startup, page-two tag fetch, and 20k-file sidecar matching are bounded.
- [ ] Record backfill completion and query only missing credits when a migration is required.
- [ ] Push tag membership sorting/pagination into bounded persistence queries or a reusable indexed snapshot.
- [ ] Pre-index lyrics by directory and normalized basename once per scan.
- [ ] Balance every same-parent bookmark `startAccessing` with an exact stop on commit/cancel while retaining one active scope.
- [ ] Run the full affected suites.

### Task 6: Full release/performance gate and adversarial review

**Files:**
- Modify only defects found by review.

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: source-bound release dry run and bounded fake-remote/large-library evidence.

- [ ] Run release dry-run contracts, all remote tests, 50k/100k fixture performance tests, and the full suite.
- [ ] Dispatch a fresh reviewer focused on provenance bypasses, cancellation retention, credential residue, and asymptotic regressions.
- [ ] Fix every Critical/Important finding and repeat targeted/full gates.
- [ ] Verify no network credential, signing identity, real cache, real catalog, tag, commit, or remote state was changed.
