# Cadence Interface Coherence Verification

Date: 2026-08-24
Branch: `qenterra/cadence-interface-coherence`
Worktree: temporary isolated feature worktree

## Acceptance ledger

| ID | Delivered behavior | Automated evidence | Manual boundary |
| --- | --- | --- | --- |
| CUI-01 | Track, Album, Year, and Time widths come from one non-user-resizable policy; compact mode removes optional columns before crushing content. | `TrackTableColumnPolicyTests`, `SecondAuditPresentationTests`, temporary minimum/wide frames. | Resize the installed window continuously and confirm the cursor never offers a column-resize interaction. |
| CUI-02 | The native title label uses the complete rectangle left after artwork and controls. | Native AppKit layout assertions and minimum/wide frames show full fixture titles. | Check unusually long real-library titles at the minimum supported window. |
| CUI-03 | Format and LRC badges are removed from track rows. | Row projection and native-cell tests; temporary All Tracks frames. | None beyond real-library smoke testing. |
| CUI-04 | Selection and focus use Cadence monochrome surfaces instead of system blue. | Chrome-presentation and selection tests. | Keyboard-focus and VoiceOver visual check in the installed app. |
| CUI-05 | Reused rows reset hover and press state when represented track identity changes. | AppKit reuse/performance tests. | Scroll with a stationary pointer and confirm hearts do not leak between rows. |
| CUI-06 | Favorite hearts use the white Cadence accent with bounded press feedback and Reduce Motion fallback. | Favorite state, reuse, and presentation tests. | Feel the click animation with normal and Reduce Motion settings. |
| CUI-07 | Album and artist controls occupy rendered text plus normal padding, not an entire column. | Native hit-frame and action-routing tests. | Click immediately beside long and short labels in a real table. |
| CUI-08 | Album and artist labels become primary on hover and keep the same tone while pressed. | Hover/pressed presentation tests. | Pointer acceptance in the installed app. |
| CUI-09 | Catalog artwork cards use a fixed 196-point width; only column count changes. | Semantic layout tests and Home/album minimum/ideal/wide renders. | Inspect real artwork and localized long labels. |
| CUI-10 | Favorites type selection is one inline Tracks / Albums / Artists segmented picker. | `LibraryUXInfrastructureTests`; production render. | Pointer and keyboard selection check. |
| CUI-11 | Sidebar Settings is one flat reorderable list with cross-former-category moves. | `NavigationRailTests`, settings presentation tests, rendered Sidebar tab. | Drag several destinations across the old category boundaries. |
| CUI-12 | Every sidebar destination and expansion icon is static; activation counters, symbol effects, and replacement transitions are removed. | Navigation presentation/source assertions. | Confirm no residual motion when rapidly changing destinations. |
| CUI-13 | Destination shell switches immediately and shows a native indeterminate loading state only without resident content; no fake delay. | Destination presentation tests in `LibraryUXInfrastructureTests`. | Exercise a large on-disk library and judge perceived responsiveness. |
| CUI-14 | Home, Library/Tracks, Albums, Artists, Favorites, Playlists, Tags, Smart Collections, Search, and Trash have scoped pull-to-refresh. AppKit tables use elastic pull plus `NSProgressIndicator`. | Scope routing, coalescing, stale-epoch, failure-preservation, and 72-point AppKit threshold tests. | Physical trackpad gesture and refresh-failure acceptance. |
| CUI-15 | Replaying a Recently Played item updates its timestamp, removes the old projection, and inserts it at index zero without filtering the current track. | `LibraryStoreTests` and Home projection tests. | Run against the user's persistent library. |
| CUI-16 | Player Bar artwork opens Now Playing directly on Lyrics; Queue keeps its explicit button. | `NowPlayingLifecycleTests`. | Installed-app click while a track is playing. |
| CUI-17 | Now Playing keeps its format pill and adds LRC only for an accepted synchronized document belonging to the current track. | `NowPlayingMetadataBadgesTests`; Now Playing renders. | Verify with synchronized, static, and missing lyric files. |
| CUI-18 | Queue presentation contains the current track plus at most five Up Next items while the underlying queue remains complete. | `PlaybackQueueStateTests`, `LibraryStoreTests`; rendered queue shows current + five. | Let playback advance through more than six tracks. |
| CUI-19 | The Now Playing hint is a direct-activation pill; active Cadence Mode has a top-left Back pill. | Cadence Mode state/input tests and active-mode renders. | Direct button, Z + X, Escape, and Back acceptance during playback. |
| CUI-20 | Cadence Mode artwork is capped at 560 points and has a 0.5-point translucent white border outside it. | `CadenceModeLayoutTests`, regression tests, temporary 1080×844 and 2200×1300 renders. | Check several bright/dark real covers fullscreen. |
| CUI-21 | Settings expose Enable, React to Bass, Show Synchronized Lyrics, Show Track Information, and Stay in Cadence Mode; disablement gates all activation paths. | `SettingsPresentationTests`, `CadenceModeStateTests`, persisted-default tests. | Toggle every combination while audible playback continues. |
| CUI-22 | Keyboard Reference contains Cadence Mode with literal Z + X pills. | `SettingsPresentationTests`; rendered Shortcuts tab. | Physical keyboard acceptance. |
| CUI-23 | Lyrics hide scroll indicators and follow later active lines with a calm 0.32-second transition; Reduce Motion follows immediately. | `LyricsScrollPresentationTests` and lyrics-domain tests. | Watch several synchronized tracks with both motion settings. |
| CUI-24 | A track identity change emits one non-animated top reset; automatic following starts on the next active-line change. | `LyricsScrollPresentationTests`. | Switch tracks while the first lyric panel is scrolled to the middle. |
| CUI-25 | Escape clears and unfocuses active search/tag entry before contextual Back can run. | Escape-policy, tag, search, and navigation tests. | Verify IME/composition and real text-field focus. |
| CUI-26 | Appearance changes recreate main and Settings visual subtrees while model, playback, queue, navigation, and lifecycle ownership stay outside the refreshed identity. | Appearance identity, lifecycle, AppKit recreation, and broad regression tests. | Switch system/light/dark during audible playback in the installed app. |

## Automated gates

- `xcodegen generate --spec project.yml`: passed; project regeneration is stable.
- Canonical `scripts/verify.sh`: passed on the exact feature tree, including unsigned Debug build, the complete Swift 6 test run, every visual regression suite, localization, static analysis, and product/resource checks.
- The complete Xcode test session passed in 229.714 seconds.
- The production visual matrix was regenerated after review. All 76 meaningful changed baselines were inspected across supported sizes and appearances before promotion; one comparator-only no-op candidate was discarded.
- Additional active Cadence Mode renders at 1080×844 and 2200×1300 were inspected; the temporary harness and marker were removed afterward.
- `scripts/verify_localization.sh <derived-data>`: passed with 630 active keys.
- `swiftformat Sources Tests --lint`: passed, 0 of 572 files require formatting.
- SwiftLint gate completed with 0 serious violations; the configured warning baseline remains visible.
- Periphery: passed with no unused code detected.
- `git diff --check`: passed.
- The canonical gate passed again after fast-forwarding the implementation commit into `main`; this documentation-only wording correction does not change build inputs.

## Required installed-app acceptance

Automated rendering cannot prove physical trackpad feel, stationary-pointer
hover behavior, audible playback continuity, VoiceOver output, IME composition,
or animation timing on the user's display. Those checks remain manual and are
not represented as completed by the green automated gates above.
