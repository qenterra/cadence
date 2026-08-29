# Releasing

## Authority and source

- Release owner: Nikita Melnychenko (QenTerra)
- Version scheme: semver
- Version source: `release-contract.json`
- Current version: `0.2.0-beta.1`

A local commit, tag, GitHub Release, package publication, deployment, store submission, and update-feed change are separate authorised actions.

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

1. Create an annotated release tag `v0.2.0-beta.1` at the verified commit.
2. Create a draft GitHub Release with the changelog entry, assets, checksums, support status, and known issues.
3. Inspect every asset and link before publication; use immutable releases when supported.
4. Publish only the authorised surfaces.

## Verify and recover

Compare local commit, remote branch, remote tag, release target, asset digests, package or deployment version, and update metadata. Record any unverified external surface. If publication is wrong, stop propagation, preserve evidence, use the documented rollback, and publish a new version rather than replacing immutable artifacts.
