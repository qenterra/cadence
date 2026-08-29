# Repository maintenance

## Ownership and cadence

Nikita Melnychenko (QenTerra) owns repository health, releases, security coordination, and support status. Reviews are event-driven for security or release changes, monthly for routine drift, and quarterly for provider settings; a calendar reminder is not evidence that the review happened.

## Routine review

- Weekly or event-driven: triage security alerts, dependency updates, failed workflows, support requests, and release blockers.
- Monthly: review stale issues and pull requests, flaky checks, documentation drift, dependency removals, generated artifacts, and support status.
- Quarterly: verify ownership, branch and tag rules, GitHub features, topics, security settings, private contacts, license notices, Wiki projection, and recovery instructions.
- Before every release: follow `docs/RELEASING.md` against the exact release commit.
- Before every public push: audit the canonical checkout and a fresh clean clone for agent artifacts, caches, ignored debris, and undeclared generated output.

## Dependency and security lifecycle

Record accepted update sources, lockfile ownership, vulnerability decisions, private disclosure handling, removed dependencies, and third-party notice changes. Do not merge an automated update because the automation looked confident.

## Documentation and compatibility

Retest documented setup, install, quick-start, migration, troubleshooting, and recovery paths. Mark volatile provider instructions with their verification date and update compatibility tables when support changes.

## Inactivity, transfer, and archival

If active maintenance stops, update the README and repository description with status, final supported version, replacement, security boundary, and archival date. Transfers, visibility changes, archival, deletion, and publication remain separately authorised external actions.

## Maintenance record

| Reviewed at | Scope | Evidence | Findings or changes | Next review |
| --- | --- | --- | --- | --- |
| 2026-08-29 | Repository-standard adoption | Local full gate, governance report, protected PR, and provider read-back | Pending final merge evidence | Next release or 2026-11-29 |
