# Cadence History Reconstruction Plan

Date: 2026-07-31
Design:
`docs/superpowers/specs/2026-07-31-cadence-history-reconstruction-design.md`

## Confirmed inputs

- Current public tip:
  `76c098b54f24a8ce9f88a7b9cdf58328188bb245`
- Current public history: 3 commits
- Recovered bundle:
  `/private/tmp/cadence-public-reset.NGyRAj/cadence-pre-public.bundle`
- Recovered bundle SHA-256:
  `f0abe5fc057794170085437764452bc6132b1327b8c72485933a630a607e1b03`
- Recovered main tip:
  `4682ddbe41ae4886029b6f9a4b51dcb5c7d78dd0`
- Recovered history: 34 commits
- Recovered supplemental state: 4 checkpoint trees and 1 capture tree
- Current working state: 51 changed tracked files plus approved untracked
  product files and fixtures
- Final author:
  `Nikita Melnychenko (QenTerra)
  <257410536+qenterra@users.noreply.github.com>`
- Publication is out of scope until a separate approval.

## Task 1 — Freeze the inputs

Record without changing the active index:

- `git status --short --branch`
- `git diff --binary`
- `git diff --cached --binary`
- `git ls-files --others --exclude-standard`
- local and remote refs
- current HEAD and tree IDs
- project file inventory
- source bundle refs and tree IDs

Acceptance:

- the inventories are stored outside the public repository;
- the current active `main` remains at `76c098b`;
- the user's staged and unstaged state is unchanged.

## Task 2 — Create verified recovery material

Create a dated backup directory outside the public repository containing:

1. the recovered pre-public bundle;
2. a fresh `git bundle create --all` for the current repository;
3. binary patches for staged and unstaged tracked changes;
4. a null-delimited archive of approved untracked files;
5. a complete working-tree archive excluding `.git`, build products, and
   user media;
6. ref, status, and file inventories;
7. `SHA256SUMS`.

Verify both bundles with `git bundle verify`, verify the archives can be
listed, and recheck every checksum.

Create protected local refs:

- `refs/backup/pre-reconstruction-main`
- `refs/backup/pre-reconstruction-dirty`

The dirty ref is created with a temporary index and `git commit-tree`; it must
not alter the user's index or working tree.

Acceptance:

- the clean `main`, dirty tree, and recovered pre-public history are each
  independently recoverable;
- checksums are recorded and re-read;
- no backup path is tracked by Cadence.

## Task 3 — Build the evidence ledger

Create a private TSV/JSON ledger from:

- all 34 recovered commits with full metadata;
- the five recovered tree refs;
- Cadence changelog entries from 2026-07-24 through 2026-07-31;
- relevant session timestamps and exact historical commit output;
- differences between the recovered tip, published root, published tip, and
  approved dirty tree.

For every proposed commit record:

- stable sequence number;
- subject and body;
- author and committer timestamps;
- evidence references;
- source tree or patch;
- path group;
- dependencies;
- verification gate;
- timestamp confidence.

Acceptance:

- every public candidate commit has at least one evidence source;
- no changelog-only milestone claims an exact source snapshot;
- all exact recovered timestamps remain unchanged.

## Task 4 — Define the public path policy

Generate allow/deny checks for every candidate revision.

Always remove:

- `docs/superpowers/**`
- `docs/audits/**`
- `output/**`
- discarded brand factories and previews
- `brief-preview.html`
- agent, prompt, memory, handoff, and private planning files
- DerivedData, `.xcresult`, local archives, and generated build output

Retain only the approved runtime brand source:

- `brand/icon-composer/Cadence.icon/**`

Scan file contents for:

- `/Users/`
- private email addresses
- `ChatGPT`, `Codex`, `Claude`, `Anthropic`, `superpowers`
- tokens, keys, credentials, signing material, and local media paths

Expected public references such as contributor guidance are reviewed rather
than blindly deleted when a word match is ambiguous.

Acceptance:

- policy has positive and negative fixtures;
- policy scans the entire candidate history, not only its final tree.

## Task 5 — Prepare the reconstruction workspace

Create an isolated candidate repository under the verified backup workspace.
Import:

- the recovered bundle;
- the current public repository;
- the dirty snapshot ref.

Keep imported refs under a private `refs/source/` namespace. Candidate `main`
is built exclusively with `git commit-tree` and temporary index files.

Do not checkout or reset the user's active Cadence worktree.

Acceptance:

- source refs remain immutable;
- candidate commits can be recreated deterministically from the ledger;
- rerunning the builder produces the same commit IDs.

## Task 6 — Reconstruct the prototype history

Use the recovered 2026-07-25 checkpoint trees to split the original
implementation checkpoint into coherent source milestones.

Provisional sequence:

1. `chore(project): bootstrap native macOS app`
2. `feat(theme): add Soft Graphite design system`
3. `feat(library): build column browser`
4. `feat(tags): add taxonomy browser`
5. `feat(tags): add multi-item assignment editor`
6. `feat(collections): add Smart Collections`
7. `feat(collections): add listening workspace`
8. `feat(player): add Now Playing workspace`
9. `feat(queue): add editable playback queue`
10. `feat(lyrics): add synchronized lyrics`
11. `feat(albums): add album listening pages`
12. `feat(artists): add artist listening pages`

The root body discloses that the history was reconstructed from the verified
pre-public bundle after the public reset.

At the end of the phase, the candidate tree must equal the selected sanitized
checkpoint tree.

Acceptance:

- no empty milestone commits;
- each commit changes only its named subsystem plus required shared wiring;
- the phase-end tree matches the sanitized checkpoint exactly;
- XcodeGen, formatting, lint, build, and focused tests pass at the phase end.

## Task 7 — Reconstruct media organization

Split the recovered checkpoint delta using exact file groups and session
evidence:

13. `feat(artwork): add managed artwork overrides`
14. `feat(navigation): add contextual media links`
15. `fix(ui): polish metadata links and image crop`
16. `fix(queue): refine reorder interactions`
17. `refactor(import): remove Graph from the library`
18. `feat(import): add scan and review workflow`

Acceptance:

- Graph is absent from every later revision;
- Artist, Album, and Tag navigation use stable IDs;
- phase-end tree matches the corresponding sanitized recovered state;
- focused artwork, navigation, queue, and import tests pass.

## Task 8 — Reconstruct the durable library

Split the SwiftData, import, and playback work:

19. `feat(storage): add SwiftData catalog`
20. `feat(import): add transactional managed library`
21. `feat(playback): add production audio pipeline`
22. `feat(playback): monitor audio route changes`
23. `fix(import): repair metadata and embedded artwork`
24. `fix(playback): stabilize seek, lyrics, and volume`

Use recovered final file versions only where no earlier exact blob exists.
Such placement is recorded in the private ledger and must not introduce claims
of an exact deleted snapshot.

Acceptance:

- schema transitions and import transactions are internally consistent;
- the managed library path remains `~/Music/Cadence.library`;
- original media is never mutated;
- focused persistence, import, playback, and route tests pass;
- the phase-end tree matches the sanitized pre-stabilization target.

## Task 9 — Replay exact recovered stabilization commits

Reapply the sanitized product portions of recovered commits after the large
checkpoint:

25. `feat(trash): add recoverable media deletion`
26. `fix(stability): connect production search and tags`
27. `feat(playlists): add durable ordered playlists`
28. `feat(library): unify track tables and sorting`
29. `fix(ui): unify navigation and collection layouts`
30. `feat(lyrics): persist editor changes`

Internal specs, audits, discarded brand work, and generated visual
explorations are removed before tree creation. Empty internal-only commits are
not retained.

Acceptance:

- original product diffs are preserved where their exact commits survive;
- author dates remain exact;
- private author email is replaced with GitHub noreply;
- schema, Trash, playlists, collections, and lyrics tests pass.

## Task 10 — Replay the clean public reset

Apply the product and public-documentation delta from the recovered tip to the
current public root:

31. `chore(brand): integrate the Cadence app icon`
32. `docs(repo): publish project documentation`
33. `ci: add repository verification`

Do not reintroduce:

- `DESIGN.md`
- old brand factories
- `docs/superpowers`
- `output`
- local audit reports

Acceptance:

- public metadata remains version 0.1.0 build 1;
- README images and legal files contain no private paths;
- the candidate tree equals the sanitized published tip before dirty changes.

## Task 11 — Integrate the approved dirty tree

Partition the current 51-file change set into evidence-backed commits:

34. `refactor(fixtures): remove production mock content`
35. `feat(tags): add batch track assignment`
36. `fix(ui): standardize workspace layouts`
37. `feat(settings): finish About and sidebar controls`
38. `test: cover production empty states and tag assignment`
39. `docs(ui): document the shared layout system`

The exact count may shrink when tests belong in the same atomic commit as
their implementation.

Acceptance:

- the candidate final tree equals the approved dirty snapshot;
- deleted mock models are absent from production;
- deterministic fixtures remain under tests;
- generated project files agree with `project.yml`.

## Task 12 — Validate every revision

For each candidate commit:

- verify one parent except the root;
- verify author, email, dates, and message policy;
- run `git diff-tree --check`;
- run the full-history path and content policy;
- reject empty commits and unexplained binary additions;
- record tree ID and check result in the ledger.

At each phase boundary:

- generate the Xcode project;
- run SwiftFormat and SwiftLint;
- build the application;
- run focused tests.

Acceptance:

- the history is linear;
- every revision passes policy;
- every phase boundary builds and tests.

## Task 13 — Validate the final candidate

Run:

- `bash scripts/verify.sh`
- clean source-only repository audit
- full-history private-path and AI-material scan
- final tree comparison against the dirty snapshot
- app version, bundle metadata, icon, and deployment-target checks
- log, author, timestamp, and contributor review

Produce:

- candidate commit map;
- original-to-reconstructed milestone map;
- exact final tree ID;
- test and build report;
- list of any manual GUI or audio checks that remain.

Acceptance:

- all automated checks pass;
- no unexplained final-tree difference exists;
- current user worktree remains unchanged.

## Task 14 — Attach the candidate locally

Import the verified candidate as:

- `refs/heads/qenterra/reconstructed-history`

Do not move `main`, `origin/main`, or create a tag. Show the user:

- `git log --reverse`;
- commit count and author summary;
- original and candidate tree comparisons;
- verification report;
- backup locations and checksums.

Acceptance:

- the candidate is reviewable from the existing repository;
- public GitHub state is unchanged;
- publication requires a new explicit approval.

## Task 15 — Publish only after approval

After a separate approval:

1. read the current remote `main` ID again;
2. push with an exact `--force-with-lease`;
3. read back remote refs and GitHub commit history;
4. wait for hosted CI;
5. clone the public repository into a fresh directory;
6. verify commit count, tree ID, history policy, and build metadata;
7. retain backup refs and bundles.

No GitHub Release or tag is created.
