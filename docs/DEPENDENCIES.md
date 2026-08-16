# Dependencies

Cadence uses Apple platform frameworks and three pinned Swift packages at
runtime, plus six Homebrew tools during development and release packaging.

## Runtime

| Component | Version policy | Role | Source |
| --- | --- | --- | --- |
| Cadence | `0.2.0-beta.1` | Application | This repository |
| Swift and SwiftUI | Active compatible Xcode | Language and interface | Apple |
| SwiftData | Active macOS SDK | Library persistence and migration | Apple |
| AVFoundation and AVFAudio | Active macOS SDK | Audio inspection and playback | Apple |
| AppKit, Foundation, Observation | Active macOS SDK | macOS integration and app infrastructure | Apple |
| CoreAudio and AudioToolbox | Active macOS SDK | Audio route and format services | Apple |
| CoreImage | Active macOS SDK | Artwork processing | Apple |
| CloudKit | Active macOS SDK | Private iCloud library and media synchronization | Apple |
| MediaPlayer | Active macOS SDK | Now Playing and remote commands | Apple |
| UniformTypeIdentifiers | Active macOS SDK | File and library package types | Apple |
| GRDB.swift | Exactly `7.10.0` | Derived SQLite FTS5 index for lyrics search | [groue/GRDB.swift](https://github.com/groue/GRDB.swift) |
| AppAuth | Exactly `2.1.0` | OAuth 2.0 authorization and token refresh for Google Drive | [openid/AppAuth-iOS](https://github.com/openid/AppAuth-iOS) |
| Sparkle | Exactly `2.9.5` | Signed in-app software updates with stable and beta channels | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) |

GRDB, AppAuth, and Sparkle are locked in `Package.resolved`; none introduces analytics. GRDB owns
only the rebuildable lyrics-search index, never the canonical library. AppAuth
stores Google authorization state through Cadence's Keychain adapter. Sparkle
uses an EdDSA public key in the app; its private signing key remains outside the
repository in the maintainer's Keychain.

## Development tools

| Formula | Version policy | Role | License |
| --- | --- | --- | --- |
| `xcodegen` | Homebrew-resolved | Generate the Xcode project | MIT |
| `swiftformat` | Homebrew-resolved | Check Swift formatting | MIT |
| `swiftlint` | Homebrew-resolved | Check Swift style and common mistakes | MIT |
| `xcbeautify` | Homebrew-resolved | Format Xcode build output | MIT |
| `python@3.14` | Homebrew-resolved | Run release-contract, Finder-layout, and image tests | Python-2.0 |
| `periphery` | Homebrew cask | Reject newly unreachable Swift declarations | MIT |

`Brewfile` declares these tools. The repository does not lock Homebrew formula
versions, so a clean build is toolchain-reproducible by policy rather than by a
complete binary lockfile. `release/requirements.txt` pins `ds_store` and
`mac_alias` for the native macOS 27 Finder layout and retains `dmgbuild` only
for the explicit pre-macOS-27 compatibility branch. The release script installs
them into the ignored `.build/release-tools` virtual environment. macOS 27 uses
`diskutil image`; it never invokes dmgbuild's deprecated `hdiutil` workflow.

## Evaluated alternatives

Dependencies are added only when they remove more product risk than they add.
The following libraries were reviewed during the 0.2 beta audit and are not
runtime dependencies:

| Candidate | Decision | Rationale |
| --- | --- | --- |
| [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) | Do not adopt for 0.2 | Its decoders, player, conversion, and writable metadata model are valuable for broader format support. Cadence currently targets formats supported by Apple's audio stack, so replacing the tested AVFoundation/AVFAudio path would expand the binary, licensing review, and playback surface without solving a confirmed beta defect. Re-evaluate only if a supported-format or gapless-playback acceptance test proves the native stack insufficient. |
| [SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing) | Keep as a later test-only option | It provides recording and image, text, and data snapshot strategies. Cadence's existing native RGBA comparator already gives deterministic macOS screenshot diffs and is integrated into the release gate. Consider a hybrid adoption when hierarchy or serialized-state snapshots become a concrete need; replacing the current image gate alone would add migration work without broader coverage. |

These are deliberate boundaries, not fallback implementations. A future change
must start with a failing product-level acceptance test, document licensing and
binary-size impact, and retain one authoritative playback or snapshot path.

## Updating the toolchain

1. Review the new macOS and Xcode requirement.
2. Update `project.yml`, documentation, and CI together.
3. Regenerate `Cadence.xcodeproj`.
4. Run `scripts/verify.sh`.
5. Manually check playback routes and the affected interface on macOS.
