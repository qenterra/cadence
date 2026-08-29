# Track-list performance verification — 2026-08-24

## Scope

- Branch: `qenterra/cadence-release-recovery`
- Starting HEAD: `84549bff2d26360ab8dd2fb5a41dc7060754c666`
- The working tree already contained unrelated user changes. This work did not reset, commit, push, sign, or release anything.
- Build and tests reused one bounded artifact set under `/private/tmp/cadence-track-list-*` with `-jobs 2`.

## Architecture under test

- Production track rows use reusable AppKit cells instead of a SwiftUI `NSHostingView` per visible row.
- Cells are layer-backed and use Core Animation for selection, artwork, and artwork cropping. Metal and unconditional layer rasterization are intentionally not used.
- Row text and state are supplied through immutable, preformatted display projections held in a fixed-capacity cache.
- Reconfiguration diffs content, layout, and chrome independently; selection-only changes do not rewrite row content.
- Append, tail removal, single-row move, and stable-ID mutation use targeted table updates rather than unconditional full reloads.
- Artwork requests are pixel-bounded, cancellable, and guarded against stale completion after cell reuse.
- All Tracks and Favorites use virtual repository-backed windows with 64-row pages and at most five resident pages (320 projections). Search and smart-collection results remain paginated/materialized sources but use the same native production renderer.
- All Tracks and Favorites resolve playback queues from the repository rather than from only the resident viewport.

## Automated evidence

### Build

`xcodebuild build-for-testing` completed with `** TEST BUILD SUCCEEDED **` under Swift 6 using the configured Xcode toolchain.

### Focused tests

`xcodebuild test-without-building` completed with `** TEST EXECUTE SUCCEEDED **`:

- 82 tests in 4 suites passed in 41.223 seconds.
- Suites: `AllTracksPerformanceTests`, `FavoriteCatalogPaginationTests`, `ProductionPlaybackAppModelTests`, and `TrackWindowRepositoryTests`.
- Result bundle: `/tmp/cadence-track-list-derived/Logs/Test/Test-Cadence-2026.08.24_10-32-11-+0200.xcresult`

### 10,000-row AppKit benchmark

| Renderer/profile | p50 | p95 | max |
| --- | ---: | ---: | ---: |
| Production native, sequential row | 2.018 ms | 5.079 ms | 5.380 ms |
| Production native, viewport jump | 9.986 ms | 11.743 ms | 12.512 ms |
| Previous hosted row, sequential row | 3.991 ms | 4.899 ms | 5.050 ms |
| Previous hosted row, viewport jump | 27.896 ms | 30.068 ms | 30.232 ms |

The native viewport-jump p95 is about 2.56 times faster than the previous hosted-row path. The sequential-row p95 is within an 8.33 ms 120 Hz event budget; a whole viewport jump still exceeds one 120 Hz frame and must be judged in the running app.

The production native path created zero SwiftUI hosting roots during the benchmark. Its viewport run reused the existing cells and configured 576 row identities without creating new roots.

### Deep paging

- Fixture: 4,096 indexed records.
- Query: offset 4,032, limit 64.
- Measured repository fetch: 30.420 ms.
- Only the requested 64 rows were returned.

### Static checks

- `swiftformat Sources Tests --lint --cache ignore`: 0 of 567 files require formatting.
- `git diff --check`: clean.
- Focused SwiftLint completed analysis but remains red on file/type/function-size policy limits in already large table and test files. No runtime or compiler diagnostics were reported by that check.

## Manual acceptance still required

- Scroll All Tracks, Favorites, Search, a smart collection, an album/artist page, and a long playlist with the user's real library and trackpad.
- Confirm no visual regression in selection, hover controls, saved artwork crop, drag-and-drop, contextual menus, keyboard focus, and VoiceOver.
- Confirm playback and full-queue ordering from All Tracks and Favorites with audible output.
- Profile the running app with Instruments (SwiftUI, Core Animation, Hangs, and Allocations) if any hitch remains. The automated benchmark proves bounded work and a large CPU-side improvement; it does not prove physical 120 Hz smoothness on the user's display.
