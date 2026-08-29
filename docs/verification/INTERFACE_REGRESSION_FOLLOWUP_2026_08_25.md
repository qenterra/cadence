# Cadence Interface Regression Follow-up Verification

Date: 2026-08-25
Branch: `qenterra/cadence-interface-regression-followup`
Worktree: `/private/tmp/cadence-interface-regression-followup`

## Acceptance ledger

| ID | Delivered behavior | Automated evidence | Manual boundary |
| --- | --- | --- | --- |
| TRK-01 | Native rows reconcile the real pointer after scrolling and reuse; idle non-favorites stay hidden and favorites stay filled. | `AllTracksPerformanceTests` favorite visibility, selected-row, reuse, and live-scroll tests; approved All Tracks frames. | Scroll with a stationary pointer and inspect every reused row. |
| TRK-02 | Favorite changes are immediate white fill/unfill with no keyframe, bounce, replacement, or color effect. | Favorite transient-state tests plus source audit for heart-related motion. | Judge the press response in every installed-app surface. |
| TRK-03 | The title/artist stack is centered and Album, Year, and Time share the title baseline under fixed column policy. | Native geometry/frame tests, `TrackTableColumnPolicyTests`, minimum and wide All Tracks frames. | Check unusually long real metadata at the minimum supported width. |
| TRK-04 | Selected rows use only Cadence selection fill; hover uses the quieter fill; the white focus stroke is gone. | Native chrome presentation tests and approved All Tracks frames. | Inspect keyboard focus, mixed hover, and multi-selection in the installed app. |
| TRK-05 | Control and Command toggle tracks, Shift selects a range, and context selection is resolved before bulk actions. | `AllTracksPerformanceSelectionTests` and coordinator integration test. | Exercise physical Control/Command plus secondary click. |
| CAT-01 | Plain catalog clicks activate immediately; Control/Command and Shift update stable-ID album, artist, and playlist selections without activation. | RED then GREEN `TrackSelectionControllerTests`; production views pass event modifiers and sorted targets. | Exercise physical modifier clicks on each catalog surface. |
| CAT-02 | Album and artist menus show direct field choices followed by Ascending/Descending choices. | `LibraryUXInfrastructureTests` direct sort-state test and localization compiler metadata. | Open both native menus and inspect checkmarks/keyboard navigation. |
| CAT-03 | Shared row/card presses no longer apply symbol effects; Home track tiles have no trailing play triangle. | Accessibility and library UX presentation tests; approved Home frames; source audit. | Judge press feedback on a real display. |
| CAT-04 | Cadence Mode Back is the standard plain secondary `chevron.left` label. | Approved Cadence Mode frames and source inspection. | Verify pointer target and contrast over several live backgrounds. |
| HOME-01 | Artist card context menus expose Pin to Home and Unpin from Home. | Production context action inspection and shared pin-store tests. | Invoke both menu states against persistent pins. |
| HOME-02 | Pinned albums, artists, playlists, and smart collections render as separate typed shelves. | Typed projection test and approved Home baseline matrix. | Verify mixed real pins and shelf ordering. |
| PLS-01 | New Playlist from track actions opens a name alert before creation and retains captured ordered track IDs. | Store return-ID test, pending-request/cancel/failure tests, focused model suites. | Confirm initial text-field focus and Cancel/Create with a real library. |
| SHELL-01 | Smart Collections mounts its page-owned loading lifecycle instead of waiting behind the root spinner. | Destination-aware loading regression in `LibraryUXInfrastructureTests`. | Open against a cold large library and exercise empty/error states. |
| NOW-01 | Standard Now Playing scrolls vertically when needed and keeps the Cadence Mode hint above the player. | `CadenceModeLayoutTests` overflow policy and `qa-now-playing-min-dark.png`. | Resize continuously and use a track with long metadata/tags. |
| NOW-02 | Artwork/card symbols no longer bounce or morph when the containing control is clicked. | Same static-symbol tests and source audit as CAT-03. | Judge real press behavior. |
| LRC-01 | The lyrics editor clock reads the playback presentation clock at 30 Hz and reserves monospaced width. | `ProductionPlaybackAppModelTests` presentation-time regression and focused build. | Watch the live clock while playing, pausing, and seeking. |
| SET-01 | Persistent Settings booleans inherit native macOS switch style. | Settings policy test plus approved General, Sidebar, and Updates frames. | Click and keyboard-toggle each Settings switch. |

## Automated gates

- Focused RED then GREEN coverage was recorded for favorite ownership, native row geometry and context selection, catalog selection, Home pin grouping, named playlist requests, Smart Collections mounting, Now Playing overflow, lyrics timing, and Settings switches.
- The combined focused suites passed: `AllTracksPerformanceTests`, `AllTracksPerformanceSelectionTests`, `TrackSelectionControllerTests`, `LibraryUXInfrastructureTests`, `LibraryStoreTests`, `ProductionPlaybackAppModelTests`, and `CadenceModeLayoutTests`.
- After reviewed baseline promotion, the complete `scripts/verify.sh` run passed release-contract tests (87/87), DMG tests (5/5), SwiftFormat (0/575 files), SwiftLint (171 warnings and 0 serious findings), every Xcode suite including screenshot acceptance, localization, Periphery, and built-product checks.
- After the final first-click and localization corrections, `TrackSelectionControllerTests` and `LibraryUXInfrastructureTests` passed again.
- Localization passed with 632 active keys. Periphery reported no unused code. Built-product plist, registered audio extensions, icon resources, and light/dark asset entries were inspected and passed.
- `git diff --check` passed before this evidence file was added and is repeated in the final audit.

## Visual evidence

The canonical `scripts/update_screenshots.sh` workflow rendered all 86 candidates under:

`/var/folders/p6/0p3k8_9j1q72q5_8zvmhk9vw0000gn/T/CadenceVisualRegression/update`

Pixel comparison against the previous baselines identified 51 meaningful changed frames and nine byte-only or sub-threshold candidates. Every meaningful frame was inspected in old/new review sheets before promotion; the nine noise-only candidates were restored. The approved matrix covers All Tracks, album/library track rows, typed Home pins, Settings switches, and Cadence Mode Back/transition states. It shows corrected baselines, stable fixed columns, hidden idle hearts, separate pinned shelves, native switches, the native Back control, and compact fullscreen artwork. The complete screenshot gate then passed against the 51 promoted baselines.

## Required installed-app acceptance

Automated policies and static frames cannot prove stationary-pointer scrolling,
physical modifier/context clicks, native menu behavior, alert focus, animation
feel, or a clock advancing during audible playback. Those checks remain manual
and are not represented as completed by the local gates above.
