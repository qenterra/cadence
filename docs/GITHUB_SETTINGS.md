# GitHub settings and verification

Repository files declare expected behavior but do not prove live GitHub settings. Verify the exact repository through an authorized API query or settings review and retain the evidence with the adopting task.

## Metadata and features

Confirm the canonical owner and repository URL, description, homepage, topics, visibility, default branch, and the Issues, Discussions, Wiki, and Projects switches declared in `.github/qenterra-repository.json`. Disable a surface that has no owner or workflow.

## Branch and tag rules

- Protect `main` against deletion and force pushes.
- Require focused pull requests, the project gate, `repository-governance`, conversation resolution, and linear history.
- Require independent approval and Code Owner review for team repositories; record honest self-review for solo repositories.
- Restrict bypass, preserve emergency evidence, and protect release tags from replacement.

## Merge and lifecycle settings

Enable squash merge, disable unused merge methods, delete merged head branches, and keep the default branch at `main`. Record any long-lived release-branch exception and its support window.

## Security and supply chain

Review dependency graph, Dependabot alerts and updates, secret scanning, push protection, code scanning, private vulnerability reporting, workflow permissions, environment protection, artifact attestations, and immutable releases where supported and applicable.

## Verification record

| Checked at | Exact repository | Evidence source | Reviewer | Result | Unverified or exception |
| --- | --- | --- | --- | --- | --- |
| 2026-09-16T19:33Z | https://github.com/QenTerra/cadence | Post-publication GitHub API, ruleset, ref, release, label, and fresh Wiki-clone read-back | Repository audit | Passed: `main` at `d193b685`, Wiki at `2841be4a`, metadata and feature switches aligned, squash-only merge and branch deletion retained, branch and `v*` tag rules active, 21 governed labels synchronized, Dependabot alerts and security updates enabled, private vulnerability reporting enabled, secret scanning and push protection enabled, Actions SHA pinning enabled with `allowed_actions: all`, and immutable releases enabled; the corrected `v1.0.0` body, tag, and three asset digests were verified and the release is immutable | Code scanning remains intentionally unconfigured. Enabling Swift CodeQL requires a separate Xcode-27-compatible workflow review and explicit build authority. |
| 2026-09-16T19:00Z | https://github.com/QenTerra/cadence | Pre-publication GitHub API, ruleset, release, asset, and Wiki read-back | Repository audit | Mixed: public visibility, metadata, `main`, Issues, Wiki, squash-only merges, branch deletion, required PR checks, protected `v*` tags, secret scanning, push protection, release assets, and the pre-audit Wiki projection verified | Private vulnerability reporting, Dependabot alerts and security updates were disabled; code scanning was not configured; Actions permitted all actions without SHA enforcement; live labels did not match `.github/labels.yml`; future-release immutability was disabled. This row records the state before publication, not the intended final state. |
| 2026-08-29 | https://github.com/QenTerra/cadence | Authorized GitHub API, Actions, and ruleset read-back after protected publication | Nikita Melnychenko (QenTerra) | Passed: public visibility, `main`, Issues, Wiki, squash-only merges, branch deletion, required PR checks, and immutable `v*` tags verified | Code scanning, signing, notarization, and release assets remain release-specific checks |

Never copy a prior repository’s result forward. Provider features, plan availability, and settings can change without a source diff.
