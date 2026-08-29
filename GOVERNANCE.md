# Governance

Cadence is maintained by Nikita Melnychenko (QenTerra) under the QenTerra repository standard.

## Authority

- Maintainers own issue triage, review, merge, version, release, and security decisions for their declared areas.
- Material changes use a focused pull request and the checks in `CONTRIBUTING.md`.
- Commit, push, tag, release, deployment, and GitHub-setting changes remain separate authorised actions.
- Security disclosures use the private route in `SECURITY.md`.

## Decisions

Durable architectural choices are recorded under `docs/decisions/`. Superseded decisions remain readable and point to their replacements.

| Change class | Required path |
| --- | --- |
| Routine maintenance | Focused pull request, declared checks, responsible maintainer review |
| Public API, data format, compatibility, security, privacy, or governance | Design rationale, migration or recovery plan, explicit owner decision, and release impact |
| Emergency security repair | Smallest safe private coordination, preserved evidence, and retrospective review after disclosure |

Technical disagreement is resolved from the stated requirements, primary evidence, and project invariants. When reasonable options remain, the responsible maintainer records the decision and trade-off; silence and merge access are not architectural arguments.

## Maintainers

Current responsibility is listed in `MAINTAINERS.md` and `.github/CODEOWNERS`. Ownership grants responsibility, not an exemption from review or verification.

Maintainer addition, role change, recusal, or removal updates `MAINTAINERS.md`, `CODEOWNERS`, protected settings, security access, release authority, and private contacts together. The change records who approved it and when access was verified.

## Succession and inactivity

When a maintainer leaves or the project becomes inactive, update ownership, support status, repository description, README, and archival or replacement links in one reviewed change.
