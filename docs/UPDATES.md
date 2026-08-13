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
- The current distribution is ad-hoc signed because no Apple Developer ID is
  available. macOS may therefore show Gatekeeper friction on the first manual
  installation. EdDSA still protects subsequent Sparkle downloads, but it is
  not a substitute for Apple notarization.

## Preparing a release

`qds-release.json` is the canonical release source. The current contract is
**Cadence 0.2.0 Beta 1 (2)**, tag `v0.2.0-beta.1`, Apple silicon, macOS 26 or
later. It produces exactly:

- `Cadence-0.2.0-beta.1-arm64.dmg`
- `Cadence-0.2.0-beta.1-arm64.zip`
- `Cadence-0.2.0-beta.1-SHA256SUMS.txt`

1. Make sure the release candidate passes `scripts/verify.sh` and focused live
   playback/library checks.
2. Run `scripts/prepare_release.sh [release-notes.md]`. The script validates the
   QDS contract, archives Cadence with the manifest version/build, creates the
   update ZIP and styled DMG, signs the ZIP with the Keychain EdDSA key, updates
   `appcast.xml`, and writes checksums.
3. Inspect the mounted DMG, both archive payloads, appcast diff, release notes,
   version/build values, signing output, and checksums.
4. Create the manifest tag and GitHub prerelease and upload all three named
   assets. Do not rename an asset after generating the appcast.
5. Commit and publish the updated `appcast.xml`. Read the public release and
   enclosure URL back before announcing it.

The first beta is ad-hoc signed and not notarized. Its release page and README
must keep the Gatekeeper disclosure visible. Sparkle tags the appcast item with
the `beta` channel, so stable users never receive it.
