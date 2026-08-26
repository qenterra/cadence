# Cadence Security Hardening Implementation Plan

> **For agentic workers:** execute one task at a time with a visible RED → GREEN
> cycle. No commit, push, release, or destructive Git maintenance is authorised.

**Goal:** Make Cadence's release gate reproducible and harden confirmed remote,
IPC, and managed-library trust boundaries.

**Architecture:** Use testable connection/session seams, pre-download cache
reservation, a signed bounded inter-instance envelope, and layout symlink
rejection. Keep existing provider, playback, Finder-open, and catalog flows.

**Tech stack:** Swift 6/macOS 26, XCTest/Swift Testing, XcodeGen, Bash,
GitHub Actions, Python 3.14/Pillow.

**Spec:** `docs/superpowers/specs/2026-08-25-cadence-security-hardening-design.md`

## Closure status (2026-08-26)

This file is retained as a historical implementation plan, not an open task
queue. The consolidated branch implements and verifies deterministic release
tooling, pinned dependencies, WebDAV failure cleanup and restore validation,
cache admission reservations and bounded prefetching, authenticated bounded
instance messages, and managed-library symlink rejection.

The provider-wide credential replacement test matrix and a provider-level
manifest byte cap were deliberately deferred. The shared manifest track-count
limit remains implemented. Those deferred items are outside this consolidation
and the unchecked boxes below must not be treated as active work.

## Global constraints

- Sparkle is exactly `2.9.6`; no floating package or action references.
- A partial hosted check never writes a release attestation.
- Remote cache downloads reserve capacity before provider reads.
- Finder-open remains a transient queue; only authenticated bounded messages
  are delivered to the existing handler.
- No production change precedes its focused failing regression.

---

### Task 1: Repair deterministic release verification

**Files:**
- Modify: `project.yml`, `Cadence.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Modify: `scripts/verify.sh`, `.github/workflows/ci.yml`, `Brewfile`, `README.md`
- Modify: `Tests/ReleaseContractTests/test_release_provenance.py`
- Create: `requirements-dev.txt`, `scripts/prepare_python_tools.sh`

- [ ] Add release-contract regressions proving a partial outer environment does
  not poison nested full-gate topology and fixture commands resolve to their
  shim directory; run the focused Python class and observe the current failure.
- [ ] Add a regression that a missing Pillow interpreter produces one setup
  diagnostic before `test_dmg_background.py`; run it red.
- [ ] Make `verify.sh` explicitly separate inherited hosted-skip state from
  fixture full-gate environments, validate the selected image interpreter with
  `import PIL`, and use the project setup script rather than PATH coincidence.
- [ ] Pin Pillow, Sparkle, and checkout; regenerate the Xcode project and
  resolve the exact package revision.
- [ ] Run release-contract and DMG tests green, then the hosted partial command.

### Task 2: Make Remote Media credentials transactional

**Files:**
- Modify: `Sources/Cadence/Remote/RemoteLibraryController.swift`
- Create or modify: focused remote connection factory/session support
- Modify: `Tests/CadenceTests/RemoteLibraryIntegrationTests.swift` and test support

- [ ] Add fake provider/session tests for failed WebDAV activation, failed
  Google activation, provider replacement, and insecure restored WebDAV URL.
  Assert each provisional/replaced session receives `signOut()` exactly once.
- [ ] Run the new tests red against the current controller.
- [ ] Introduce a production connection factory and pending invalidatable
  session; clean up the pending session in every failure path, validate restore
  URLs, and invalidate replaced credentials only after a new record succeeds.
- [ ] Run focused tests green and verify disconnect still clears the active
  provider and persisted record.

### Task 3: Bound Remote Media admission and manifests

**Files:**
- Modify: `Sources/Cadence/Remote/RemoteMediaCache.swift`, `RemotePlaybackSource.swift`, `RemoteLibraryManifest.swift`
- Modify: WebDAV and Google Drive provider manifest readers
- Modify: `Tests/CadenceTests/RemoteMediaCacheTests.swift`, provider contract tests

- [ ] Add tests that an oversized object performs zero provider reads, staging
  reservations block competing downloads, and an oversized following queue
  schedules only the configured prefetch window.
- [ ] Add provider tests for a manifest exceeding the declared byte cap and a
  manifest exceeding the track limit; run them red.
- [ ] Reserve bytes before reads, release reservations after success/failure,
  set bounded prefetch constants, validate the track limit, and stream/cap
  manifest bytes before JSON decoding.
- [ ] Run focused cache/provider tests green.

### Task 4: Authenticate local open-file routing

**Files:**
- Modify: `Sources/Cadence/App/CadenceInstanceCoordinator.swift`
- Create: a focused Keychain-backed message-authentication helper if extraction
  makes the coordinator testable
- Modify: `Tests/CadenceTests/CadenceInstanceCoordinatorTests.swift`

- [ ] Add tests for forged, tampered, oversized, non-file, and valid signed
  payloads; run them red.
- [ ] Implement a random Keychain secret, Codable envelope, HMAC verification,
  and strict path/batch limits while retaining ordered valid paths.
- [ ] Add `O_NOFOLLOW` to the process lock open path when available and retain
  existing stale-lock behaviour.
- [ ] Run coordinator tests green.

### Task 5: Reject managed-library layout symlinks

**Files:**
- Modify: `Sources/Cadence/ManagedLibrary/ManagedLibraryPackage.swift`
- Modify: `Tests/CadenceTests/ManagedLibraryLocationTests.swift`

- [ ] Add a test where `Cadence` or `Cadence/Media` is a symlink to a sentinel
  directory; assert bootstrap throws and the sentinel receives no created
  layout or identity file. Run it red.
- [ ] Reject symbolic links for the package and each required directory before
  directory creation; preserve ordinary idempotent bootstrap.
- [ ] Run managed-library location/import focused tests green.

### Task 6: Final verification and adversarial review

**Files:** all changed files only.

- [ ] Regenerate XcodeGen output and confirm only expected generated changes.
- [ ] Run formatting, lint, all Python release contracts, all focused Swift
  tests, then `scripts/verify.sh` with the declared Python environment and
  Xcode 27.
- [ ] Inspect the final diff for credential logs, relaxed URL/path checks,
  unbounded queues, accidental baseline updates, or generated artefacts.
- [ ] Perform a read-only adversarial review and rerun any affected checks.
