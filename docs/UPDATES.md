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

1. Make sure the release candidate passes `scripts/verify.sh` and silent manual
   playback/library checks.
2. Run `scripts/prepare_release.sh <version> <build> <stable|beta>
   [release-notes.md]`. The script archives Cadence, creates the update ZIP,
   signs it with the Keychain EdDSA key, and updates `appcast.xml`.
3. Inspect the archive, appcast diff, release notes, and version/build values.
4. Create GitHub release tag `v<version>` and upload the ZIP printed by the
   script. Do not rename the asset after generating the appcast.
5. Commit and publish the updated `appcast.xml`. Verify its enclosure URL from
   a clean machine before announcing the release.

For a beta, use a prerelease version such as `0.2.0-beta.1`, select `beta`, and
mark the GitHub release as a prerelease. Sparkle tags that appcast item with the
`beta` channel, so stable users never receive it.
