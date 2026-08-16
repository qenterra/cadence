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

## Preparing a release

`release-contract.json` is the canonical release source. The current contract is
**Cadence 0.2.0 Beta 1 (2)**, tag `v0.2.0-beta.1`, Apple silicon, macOS 26 or
later. It produces exactly:

- `Cadence-0.2.0-beta.1-arm64.dmg`
- `Cadence-0.2.0-beta.1-arm64.zip`
- `Cadence-0.2.0-beta.1-SHA256SUMS.txt`

1. Make sure the release candidate passes `scripts/verify.sh` and focused live
   playback/library checks.
2. Store notarization credentials once with `xcrun notarytool
   store-credentials`, then set `CADENCE_DEVELOPER_ID_APPLICATION`,
   `CADENCE_DEVELOPMENT_TEAM`, and `CADENCE_NOTARY_KEYCHAIN_PROFILE`.
3. Run `CADENCE_RELEASE_MODE=public scripts/prepare_release.sh
   [release-notes.md]`. The script validates the release contract, archives Cadence
   with hardened runtime and Developer ID, notarizes and staples the app and
   DMG, creates the Sparkle-signed update ZIP, updates `appcast.xml`, and writes
   checksums. Any missing identity, profile, accepted submission, ticket, or
   Gatekeeper assessment stops the process.
4. Inspect the mounted DMG, both archive payloads, appcast diff, release notes,
   version/build values, signing output, and checksums.
5. Create the manifest tag and GitHub prerelease and upload all three named
   assets. Do not rename an asset after generating the appcast.
6. Commit and publish the updated `appcast.xml`. Read the public release and
   enclosure URL back before announcing it.

For layout or mount/copy/launch testing without credentials, run
`CADENCE_RELEASE_MODE=local scripts/prepare_release.sh`. This path creates only
an ad-hoc DMG under `.build/releases/local`; it cannot mutate the appcast or
produce public update assets. Sparkle tags the public appcast item with the
`beta` channel, so stable users never receive it.
