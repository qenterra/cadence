# Cadence History Reconstruction

Date: 2026-07-31
Status: Approved for planning
Owner: Nikita Melnychenko (QenTerra)

## Objective

Replace Cadence's three-commit squash history with an evidence-backed,
reviewable account of how the application reached its current source state.
The reconstructed history must end at the presently approved working tree,
including the uncommitted cleanup and layout changes, while keeping every
public revision free of internal agent material, private data, temporary
artifacts, and discarded experiments.

This is a reconstruction, not a recovery of the deleted Git objects. It must
not claim that recreated object IDs or inferred timestamps are original.

## Evidence hierarchy

Commit boundaries and descriptions use the strongest available evidence in
this order:

1. surviving Git objects and exact command output;
2. Codex session records containing commit output, patches, or file snapshots;
3. dated Cadence entries in the Obsidian changelog;
4. approved specifications and public architecture documentation;
5. dependency analysis of the approved final source tree.

The changelog establishes the product chronology but is not sufficient on its
own to recreate exact file contents. A milestone is omitted or merged with an
adjacent milestone when its implementation cannot be supported by the
available evidence.

## Reconstruction ledger

The work uses a private ledger outside the public history. Each candidate
commit records:

- subject and optional body;
- author and committer timestamps;
- evidence references;
- files and symbols introduced or changed;
- predecessor dependencies;
- expected verification level;
- timestamp confidence: exact, session-derived, or day-only;
- any known difference from the deleted historical snapshot.

The ledger is an implementation artifact. It is not committed to the public
Cadence branch.

## Commit model

The target is approximately 30 to 45 atomic Conventional Commits. The exact
count follows the evidence and dependency graph rather than a quota.

### Phase 1 — Foundation

- create the XcodeGen project and native macOS application target;
- establish the initial app shell and tests;
- introduce the Soft Graphite design system and stable title bar.

### Phase 2 — Library workspace

- introduce the Artist → Album → Track column library;
- add track tables, sorting, selection, preview, and player surfaces;
- consolidate reusable list, separator, and workspace layout components.

### Phase 3 — Organization and listening pages

- add tag taxonomy, assignment, inheritance, exclusions, and suggestions;
- add Smart Collections and their rule model;
- add Albums and Artists listening pages;
- add artwork placeholders, overrides, crop, and contextual navigation.

### Phase 4 — Now Playing

- add Now Playing and the playback queue;
- add static and line-level synchronized lyrics;
- add queue editing, track navigation, and artwork haze.

### Phase 5 — Durable library

- add SwiftData schemas and repository projections;
- add managed import into `~/Music/Cadence.library`;
- add metadata, embedded artwork, LRC matching, hashing, transactions, and
  launch recovery;
- remove Graph from the application.

### Phase 6 — Production playback

- add the shared playback coordinator and PCM/native routing;
- add seek, volume, gain ramps, gapless boundaries, and crossfades;
- add route monitoring, system media commands, and persisted listening modes;
- fix live metadata, artwork, lyrics, and playback regressions.

### Phase 7 — Stabilization

- add recoverable Trash for tracks, albums, and artists;
- add durable ordered playlists and SwiftData migration;
- connect production tags, search, and contextual actions;
- add the durable Lyrics Editor and managed LRC recovery.

### Phase 8 — Public product state

- finish system toolbar, navigation rail, shared page layouts, and themes;
- remove shipping mock content and move deterministic data to test fixtures;
- integrate the approved app icon and application metadata;
- add About, public documentation, CI, and repository policy;
- include the current uncommitted Tags, layout, About, fixture, and cleanup
  changes in their evidence-backed final milestones.

## Authorship and dates

All recreated commits use:

```text
Nikita Melnychenko (QenTerra)
257410536+qenterra@users.noreply.github.com
```

Exact historical timestamps are retained when surviving Git or session output
provides them. Session-derived timestamps are used when the implementation
event is known but the original commit timestamp is not. When only a date is
known, commits receive deterministic increasing times in the
`Europe/Prague` timezone. The ledger records this lower confidence.

Author and committer dates match for reconstructed commits unless surviving
evidence proves otherwise.

## Commit-message policy

Subjects follow Conventional Commits:

```text
<type>(<scope>): <imperative summary>
```

Subjects are specific, use imperative mood, and remain below 72 characters.
Bodies are used only for migrations, data-integrity constraints, non-obvious
architecture decisions, or reconstructed-history disclosure. Messages do not
mention agents, prompts, chat instructions, or implementation theatrics.

The root commit body states once that the public history was reconstructed
from dated project records after the original local Git objects were removed.
Individual commits do not repeat that disclaimer.

## Clean-tree policy

No reachable public revision may contain:

- `.agents`, `.codex`, internal handoff or memory files;
- `docs/superpowers`, implementation plans, prompt files, or AI audits;
- personal screenshots, local library media, credentials, or absolute home
  paths;
- build products, DerivedData, test result bundles, temporary archives, or
  generated delivery directories;
- discarded Graph code, shipping mock libraries, or inactive design
  experiments;
- secrets, private email addresses, signing identities, or local machine
  configuration.

Files required to build and document the public application remain allowed,
including generated Xcode project files when they are part of the current
repository contract.

## Intermediate-tree rules

Each commit must be coherent and reviewable. Static policy checks and
`git diff --check` run on every commit.

Not every historical micro-step can be proven buildable because its deleted
snapshot no longer exists. Compilation is therefore mandatory at the end of
each phase and for any commit that changes project generation, persistence,
import, playback, or migration boundaries. A failing intermediate commit must
be repaired, folded into its dependency commit, or removed from the sequence.
Known-broken historical states are not reproduced for nostalgia.

## Safety architecture

Before reconstruction:

1. record the local and remote tip object IDs;
2. create and verify a full Git bundle of all current refs;
3. create a protected local backup ref for the old `main`;
4. archive the complete dirty working tree, including untracked files;
5. generate a SHA-256 manifest for the archive;
6. store the current staged, unstaged, and untracked inventories;
7. build the new history in a separate temporary repository or worktree.

The user's active Cadence directory remains untouched while the candidate
history is assembled.

Temporary safety artifacts are kept outside the public repository and are not
deleted until remote verification is complete.

## Verification

### Every commit

- inspect staged paths and diff statistics;
- run `git diff --check`;
- scan the full reachable tree for forbidden paths and private patterns;
- verify author, email, dates, parent count, and message format.

### Phase boundaries

- regenerate the project from `project.yml`;
- run SwiftFormat and SwiftLint;
- build the macOS target;
- run focused tests for the phase's subsystem.

### Final candidate

- run `bash scripts/verify.sh` with Xcode 27;
- inspect the complete reachable history for forbidden content;
- compare the candidate final tree with the approved current working tree;
- review `git log`, file history, author statistics, and commit dates;
- confirm the application remains version 0.1.0 build 1;
- confirm no tag or GitHub Release is introduced.

Differences between the candidate and approved working tree are allowed only
for explicitly approved cleanup of non-product artifacts.

## Publication boundary

The candidate branch is shown to the user before publication. Replacing the
public branch requires a separate explicit approval.

Publication uses:

- a freshly read remote `main` object ID;
- `git push --force-with-lease=refs/heads/main:<old-object-id>`;
- post-push `git ls-remote` and GitHub API read-back;
- hosted CI verification;
- a final comparison between the remote tip tree and the approved candidate.

The protected backup ref and verified bundle remain available after
publication. They may be removed only through a later explicit cleanup task.

## Acceptance criteria

The reconstruction is complete when:

- the candidate history contains only evidence-backed, meaningful commits;
- all commits use the approved author identity and human-readable messages;
- the final tree includes the current uncommitted product changes;
- every reachable revision passes the clean-tree policy;
- phase gates and the final verification pass;
- the old history and dirty state have verified recoverable backups;
- the user has reviewed the local candidate;
- the remote `main` is unchanged until separate publication approval.
