# Software updates

Cadence uses Sparkle 2 for in-app updates. The app checks the signed appcast on
GitHub daily, and users can also choose **Cadence > Check for Updates…**. Stable
updates are enabled by default. Beta releases are opt-in under **Settings >
Updates**.

## Trust model

- Release archives are signed with Sparkle EdDSA. The private key is stored in
  the maintainer's login Keychain under account `com.qenterra.cadence`; it is
  never stored in this repository.
- `SUPublicEDKey` in `project.yml` verifies every downloaded archive.
- Cadence remains sandboxed. Sparkle's Installer XPC service is enabled with
  the two narrowly scoped Mach lookup exceptions documented by Sparkle.
- Public distributions must be Developer ID signed, accepted by Apple's
  notary service, and stapled. Sparkle EdDSA protects update archives in
  transit, but it is not a substitute for platform signing and notarization.
- Ad-hoc signing exists only in the explicit `local` packaging mode. Its DMG is
  a disposable acceptance artifact and must never be uploaded or announced.
- Every reusable archive is bound to the exact release-tag commit and the
  canonical full local gate attestation. Version/build equality alone is not
  provenance and never authorizes archive reuse.

## Preparing a release

`release-contract.json` is the canonical release source. The current contract is
**Cadence 0.2.0 Beta 1 (2)**, tag `v0.2.0-beta.1`, Apple silicon, macOS 26 or
later. It produces exactly:

- `Cadence-0.2.0-beta.1-arm64.dmg`
- `Cadence-0.2.0-beta.1-arm64.zip`
- `Cadence-0.2.0-beta.1-SHA256SUMS.txt`

1. Update the release contract and every release surface, commit the candidate,
   and use a dedicated clean checkout or worktree. The intended new manifest
   tag must not already name another commit.
2. Create the local annotated release tag at that exact candidate commit. The
   authoritative relationship is `HEAD == refs/tags/$TAG^{commit}`; neither
   local `main` nor `origin/main` substitutes for it. Never move or reuse a
   published tag.
3. Run `DEVELOPER_DIR=... bash scripts/verify.sh --release-attestation`.
   The complete Xcode, localization, Periphery, and built-product gate writes a
   canonical attestation only after every check passes. Completion consumes a
   one-use session bound to the exact SHA and stable wrapper process. The five
   receipts are explicit declarations made by that local wrapper, not
   hardware-backed proof of each command. Hosted partial checks and completion
   without the valid one-use begin session cannot create release evidence. The
   validator compares the physical bytes and executable mode of every tracked
   path directly with the index and tagged commit blobs; repository-defined Git
   filters are not part of that comparison. Release input roots also reject
   ignored files, cache directories, symlinks, and hard links.
4. Store notarization credentials once with `xcrun notarytool
   store-credentials`, then set `CADENCE_DEVELOPER_ID_APPLICATION`,
   `CADENCE_DEVELOPMENT_TEAM`, and `CADENCE_NOTARY_KEYCHAIN_PROFILE`.
5. Run `CADENCE_RELEASE_MODE=public scripts/prepare_release.sh
   [release-notes.md]`. The script validates the release contract, archives Cadence
   with hardened runtime and Developer ID, notarizes and staples the app and
   DMG, creates the Sparkle-signed update ZIP, updates `appcast.xml`, and writes
   checksums. It rechecks the clean tagged source after project generation and
   dependency resolution, validates the archive's embedded SHA/tag/digest
   before signing or notarization, and runs the preparation shell as leader of
   a dedicated process group supervised by the outer command. The supervisor
   forwards termination signals to that whole group, allows one bounded graceful
   shutdown interval, terminates any surviving same-group processes, waits until
   the group is absent, and preserves the intended shell or signal status. The
   preparation shell cannot remove its own authenticated operation lock. On an
   exact successful leader exit, the supervisor keeps that lock present while
   draining the complete group and finalizes it only after proving group
   absence; an abnormal or signalled preparation retains the lock. One
   cooperative release-operation lock revalidates physical
   output-directory identities around every path-consuming stage. Every
   operation checkpoint revalidates the captured SHA, tag ref, manifest bytes,
   gate evidence, and exact output contract. The tracked appcast is changed only
   after the last such checkpoint. Any mismatch stops the process.

   When the optional notes argument is omitted, its path is derived from the
   validated contract as `release/release-notes-$PUBLIC_VERSION.md`. An explicit
   caller-relative path is normalized once before the script changes directory.
   In either case it must identify one physical, single-link, tracked file under
   `release/` whose executable mode and raw bytes match the exact tagged source;
   this is checked before the operation lock and release tools begin.
6. Inspect the app provenance keys, archive attestation, mounted DMG, both
   archive payloads, appcast diff, release notes, version/build values, signing
   output, and checksums.
7. Push the already verified tag and create the GitHub prerelease only with
   separate publication authority; upload all three named assets without
   renaming them after appcast generation.
8. Commit and publish the updated `appcast.xml`. Read the public release and
   enclosure URL back before announcing it.

The scripts do not fetch, push, create, delete, or move tags. Archive reuse via
`CADENCE_REUSE_ARCHIVE=1` rejects legacy archives without schema-v1 provenance
and same-version archives from any other commit. The existing
`v0.2.0-beta.1` tag belongs to its original source commit; current recovery work
requires a new release version and tag instead of retagging Beta 1.
All release roots must be physical directories rather than symlink redirects,
existing artifact destinations must be single-link regular files, and the
public version plus artifact names are validated as single safe path components
before Xcode archive or artifact tools run.

This local attestation is a fail-closed workflow marker, not a remote or
hardware-backed attestor. It rejects stale evidence, completion without its
one-use session, wrong-source reuse, hidden tracked/index state, ignored build
inputs, Git replacement refs, and observed release-path identity changes. The
validator entrypoints use isolated Python imports, so an untracked module beside
the script is not executed before source rejection. The operation manifest has
one exact canonical schema and a token HMAC over its source, contract, owner,
directory, and output payload. Its owner identity includes PID, process group,
and native process start time; the owner PID must also be the dedicated group
leader. A live owner or any surviving member of its recorded group prevents
replacement. Automatic recovery occurs only after both the exact owner identity
and the complete group are proven absent. PID/PGID reuse, permission ambiguity,
and malformed or incomplete lock state remain fail-closed for explicit operator
   recovery instead of being guessed away. Successful preparation performs one
   last authenticated operation check, then the supervisor authenticates the
   exact manifest, token, recorded owner, leader status, and complete-group
   absence before removing the lock. The direct finalization primitive also
   rejects a live recorded group. Every nonzero or signal path leaves the lock
   in place for that recovery contract.

The operation lock serializes this workflow, but it is not an OS security
boundary against another process running as the same user. Path strings handed
to external tools cannot defeat a deliberately malicious same-user process
without stronger isolation. An operator who can rewrite tracked scripts, alter
the lock state, ignore the lock, or invoke signing credentials outside this
workflow remains outside the trust boundary; the clean tagged commit, normal
code review, credential controls, and manual release inspection are still
mandatory. An external tool that deliberately detaches into another session is
also outside the bounded group-lifetime guarantee and must be treated as part of
the trusted toolchain.

For layout or mount/copy/launch testing without credentials, run
`CADENCE_RELEASE_MODE=local scripts/prepare_release.sh`. This path creates only
an ad-hoc DMG under `.build/releases/local`; it cannot mutate the appcast or
produce public update assets. Sparkle tags the public appcast item with the
`beta` channel, so stable users never receive it.
