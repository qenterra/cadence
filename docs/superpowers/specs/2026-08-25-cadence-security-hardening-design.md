# Cadence Security Hardening Design

> **Closure note (2026-08-26):** This is a historical design record. The
> consolidated implementation covers the release, cache, local IPC,
> managed-library, WebDAV cleanup/restore, and manifest track-count controls.
> The broader provider credential-replacement test matrix and provider-level
> manifest byte cap were deferred and are not part of this completed branch.

## Goal

Close the confirmed release-pipeline and local/remote boundary defects found in
the 2026-08-24 adversarial audit without changing Cadence's managed-library,
Finder-open, or publication authority model.

## Scope and authority

This is local work on `qenterra/cadence-security-hardening`, based on
`4cb2898`. It may change Cadence source, tests, XcodeGen input/generated
project, CI, and development documentation. It must not commit, push, publish,
sign, notarize, alter a real library, access a real remote provider, or delete
unreachable Git objects.

## Requirements

### Release and dependency integrity

1. Pin Sparkle at `2.9.6` (`ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`) in both
   XcodeGen input and resolved package state. This removes the known affected
   `2.9.5` dependency while preserving exact dependency resolution.
2. Hosted CI must run a deterministic partial gate. A nested release-fixture
   full-gate test must not inherit the outer `CADENCE_SKIP_XCODEBUILD=1`; the
   explicit skip test remains red by design.
3. Release fixtures must invoke only their installed command shims, including
   XcodeGen, even when they provide a synthetic `DEVELOPER_DIR`.
4. DMG image validation must use a project-declared Python environment with a
   pinned Pillow dependency, rather than relying on whichever `python3` happens
   to be in PATH. The gate should fail before tests with an actionable setup
   message when that interpreter is missing Pillow.
5. Pin `actions/checkout` to its v7 commit
   `3d3c42e5aac5ba805825da76410c181273ba90b1` and disable persisted checkout
   credentials because the workflow never pushes.

### Remote Media safety

1. A failed WebDAV/Google connection must remove the provisional credential or
   OAuth state. A successful switch must remove the replaced provider's
   credential. Settings must never claim a disconnected state while a known
   pending session is retained.
2. Restore must apply the same HTTPS/loopback URL validation as interactive
   WebDAV connection before it restores a credential.
3. Cache admission reserves capacity before starting a download. An object
   bigger than the budget is rejected without calling the provider; staging
   reservations count toward the budget; prefetching has bounded target count
   and concurrency.
4. A manifest has a hard track-count limit. Provider implementations must cap
   manifest bytes before decoding instead of accepting an unbounded response.

### Local-process and managed-library boundaries

1. Cross-instance Finder-open notifications carry a Keychain-backed HMAC and
   bounded paths. Unsigned, oversized, malformed, or non-file messages are
   ignored. This protects against arbitrary same-user distributed-notification
   injection without changing transient Finder ordering or import behaviour.
2. `ManagedLibraryPackage.bootstrapForConfirmedImport` rejects a package or
   required layout directory that is a symlink before creating directories or
   writing identity data. Existing resolved-path guards remain in force.

## Architecture

Remote connection construction becomes an injectable pending connection with a
provider and an invalidatable credential handle. The controller activates and
persists only a successful pending connection; every catch path invalidates the
pending handle and a replacement invalidates the previous handle. This creates
observable test seams without putting test switches into production UI code.

`RemoteMediaCache` treats promised object bytes as a reservation. It rejects an
unadmittable object before reading, accounts for active staging downloads, and
only schedules a small fixed queue of speculative fetches. Providers share a
bounded manifest-payload reader.

The instance coordinator keeps its existing distributed-notification transport
but signs a Codable envelope with a random per-installation Keychain key. The
receiver accepts only envelopes it verifies and limits before URL conversion.
This is deliberately less invasive than a new XPC service while removing the
unauthenticated broadcast surface.

## Acceptance and rollback

Every changed behaviour begins with a focused failing test. Focused release,
Remote Media, coordinator, and managed-library tests must pass before the full
local gate. The final gate uses the declared Python environment and full Xcode
27. A branch diff is the rollback point; no history rewrite or external state
mutation is part of this work.

## Explicit non-goals

- No automatic `git gc`, dangling-object deletion, or history rewriting.
- No live WebDAV/Google OAuth, audio hardware, accessibility, notarization, or
  Sparkle installation acceptance claim.
- No change to Finder-open's transient queue or managed-library import policy.
