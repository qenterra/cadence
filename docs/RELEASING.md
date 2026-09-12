# Releasing

## Release text and publication updates

Follow [Release writing](RELEASE_WRITING.md) for the release title and body,
changelog categories, contributor attribution, and publication result format.
Use the complete version in the GitHub Release title; keep any native display
label separate. Prepare and review the body before publication, then read back
the title, body, target, flags, and assets from each affected provider.
A hosted draft still requires publication authority.

## Authority and source

- Release owner: Nikita Melnychenko (QenTerra)
- Version scheme: semver
- Version source: `release-contract.json`
- Current version: `1.0.0` (build 3)

A local commit, tag, GitHub Release, package publication, deployment, store submission, and update-feed change are separate authorised actions.

## Current distribution

Cadence 1.0.0 is an Apple silicon manual download for macOS 26 or later. Its
ad-hoc signature does not provide a Developer ID identity, and it is not
notarized. The release notes and installation guide disclose the Gatekeeper
implications. This release does not deliver a Sparkle update. The obsolete
feed entry for the retired beta has been removed. See [Software updates](UPDATES.md) for the distribution
boundaries and [release notes](../release/release-notes-1.0.0.md) for the public body.

## Prepare

- [ ] Confirm the exact release commit and clean tracked tree.
- [ ] Decide compatibility impact and update the single version source.
- [ ] Move user- and operator-visible `Unreleased` entries into a dated version section.
- [ ] Document migrations, deprecations, known issues, support status, and rollback.
- [ ] Review dependencies, licenses, notices, vulnerabilities, secrets, and generated artifacts.
- [ ] Run `bash scripts/verify.sh` on the intended release tree.
- [ ] Run repository governance and release-contract checks.

## Build and inspect

- [ ] Produce artifacts from the exact release commit in the declared environment.
- [ ] Verify platform signing, notarisation, package metadata, container metadata, or registry rules that apply.
- [ ] Generate SHA-256 checksums for downloadable binary assets.
- [ ] Generate an SBOM and provenance or attestation when applicable.
- [ ] Test install, upgrade, downgrade, uninstall, migration, clean-environment use, and rollback as the profile requires.

## Publish

1. Create an annotated release tag `v1.0.0` at the verified commit.
2. Create a draft GitHub Release with the changelog entry, assets, checksums, support status, and known issues.
3. Inspect every asset and link before publication; use immutable releases when supported.
4. Publish only the authorised surfaces.

## Verify and recover

Compare local commit, remote branch, remote tag, release target, asset digests, package or deployment version, and update metadata. Record any unverified external surface. If publication is wrong, stop propagation, preserve evidence, use the documented rollback, and publish a new version rather than replacing immutable artifacts.
