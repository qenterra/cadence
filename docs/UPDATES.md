# Software updates

Cadence 1.0.0 (build 3) is a **manual download** for Apple silicon Macs running
macOS 26 or later. The app is ad-hoc signed, not Developer ID signed, and
**not notarized**. This release is not delivered through Sparkle. The obsolete
appcast entry for the retired beta download has been removed. See [installation](../README.md#install-cadence)
for the DMG and Gatekeeper instructions.

Cadence also includes Sparkle 2 for separately published in-app updates. Users
can choose **Cadence > Check for Updates…**; stable checks are enabled by
default and beta releases are opt-in under **Settings > Updates**. Those
settings do not make the 1.0.0 manual download an automatic update.

## Trust model

- Sparkle update archives use EdDSA signatures. The private key is stored in
  the maintainer's login Keychain under account `com.qenterra.cadence`; it is
  never stored in this repository.
- `SUPublicEDKey` in `project.yml` verifies archives downloaded by Sparkle.
  Manual downloads are checked against the release's published SHA-256 values.
- Cadence remains sandboxed. Sparkle's Installer XPC service is enabled with
  the two narrowly scoped Mach lookup exceptions documented by Sparkle.
- The Developer ID distribution profile requires notarization and stapling.
  Sparkle EdDSA protects update archives in transit; it does not substitute
  for platform signing and notarization.
- The 1.0.0 manual distribution profile uses the exact contract values
  `signing: ad-hoc`, `notarized: false`, and `gatekeeperDisclosure: true`.
  It produces downloadable artifacts without Developer ID or Apple notarization
  and never changes the Sparkle feed. This profile still requires the exact
  clean tagged source and complete local verification.
- The separate `local` packaging mode creates a disposable DMG for installer
  checks. It does not satisfy the public release provenance gate.
- Every reusable archive is bound to the exact release-tag commit and the
  canonical full local gate attestation. Version/build equality alone is not
  provenance and never authorizes archive reuse.

## Preparing a release

`release-contract.json` is the canonical release source. The current contract is
**Cadence 1.0.0 (3)**, tag `v1.0.0`, Apple silicon, macOS 26 or
later. It produces exactly:

- `Cadence-1.0.0-arm64.dmg`
- `Cadence-1.0.0-arm64.zip` (manual application archive, not a Sparkle update)
- `Cadence-1.0.0-SHA256SUMS.txt`

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
4. Select the distribution profile in the committed contract. For 1.0.0,
   use the disclosed ad-hoc manual profile; no Developer ID or notary
   credentials are required. For a Developer ID release, store notarization
   credentials with `xcrun notarytool store-credentials`, then set
   `CADENCE_DEVELOPER_ID_APPLICATION`, `CADENCE_DEVELOPMENT_TEAM`, and
   `CADENCE_NOTARY_KEYCHAIN_PROFILE`.
5. Run `CADENCE_RELEASE_MODE=public scripts/prepare_release.sh
   [release-notes.md]`. The script validates the release contract, archives Cadence
   using the validated distribution profile. The ad-hoc profile creates the
   DMG, a manual ZIP, and checksums while skipping notarization and leaving
   `appcast.xml` unchanged. The Developer ID profile notarizes and staples the
   app and DMG, creates a Sparkle-signed update ZIP, updates `appcast.xml`,
   and writes checksums. It rechecks the clean tagged source after project generation and
   dependency resolution, validates the archive's embedded SHA/tag/digest
   before distribution processing, and runs the preparation shell as leader of
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
7. Push the already verified tag and create the GitHub Release only with
   publication authority. Match the prerelease flag to the contract channel;
   1.0.0 is stable. Upload the three named assets without renaming them.
8. Read the release body, flags, target, asset names, and checksums back from
   GitHub. For the 1.0.0 manual profile, confirm `appcast.xml` is unchanged.
   Only a Developer ID update release publishes the generated appcast; verify
   its public enclosure URL before announcing that update.

The scripts do not fetch, push, create, delete, or move tags. Archive reuse via
`CADENCE_REUSE_ARCHIVE=1` rejects legacy archives without schema-v1 provenance
and same-version archives from any other commit. A published tag always
belongs to its original source commit; corrections
require a new release version and tag instead of moving the published tag.
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
produce a verified public release. The public mode selects its distribution
profile from the validated contract; the release channel controls whether an
eligible Sparkle item belongs to stable or beta users.
