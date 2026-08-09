# Dependencies

Cadence uses Apple platform frameworks and three pinned Swift packages at
runtime, plus four Homebrew tools during development.

## Runtime

| Component | Version policy | Role | Source |
| --- | --- | --- | --- |
| Cadence | `0.1.0` development source | Application | This repository |
| Swift and SwiftUI | Active compatible Xcode | Language and interface | Apple |
| SwiftData | Active macOS SDK | Library persistence and migration | Apple |
| AVFoundation and AVFAudio | Active macOS SDK | Audio inspection and playback | Apple |
| AppKit, Foundation, Observation | Active macOS SDK | macOS integration and app infrastructure | Apple |
| CoreAudio and AudioToolbox | Active macOS SDK | Audio route and format services | Apple |
| CoreImage | Active macOS SDK | Artwork processing | Apple |
| MediaPlayer | Active macOS SDK | Now Playing and remote commands | Apple |
| UniformTypeIdentifiers | Active macOS SDK | File and library package types | Apple |
| QenTerraDesignTokens | QDS `1.9.x`, local sibling package | Semantic colors, radii, motion, and shared SwiftUI state contracts | QenTerra `design-system/packages/swift` |
| GRDB.swift | Exactly `7.10.0` | Derived SQLite FTS5 index for lyrics search | [groue/GRDB.swift](https://github.com/groue/GRDB.swift) |
| AppAuth | Exactly `2.1.0` | OAuth 2.0 authorization and token refresh for Google Drive | [openid/AppAuth-iOS](https://github.com/openid/AppAuth-iOS) |

QDS resolves from the sibling `design-system` checkout. GRDB and AppAuth are
locked in `Package.resolved`; neither introduces analytics. GRDB owns only the
rebuildable lyrics-search index, never the canonical library. AppAuth stores
Google authorization state through Cadence's Keychain adapter.

## Development tools

| Formula | Version policy | Role | License |
| --- | --- | --- | --- |
| `xcodegen` | Homebrew-resolved | Generate the Xcode project | MIT |
| `swiftformat` | Homebrew-resolved | Check Swift formatting | MIT |
| `swiftlint` | Homebrew-resolved | Check Swift style and common mistakes | MIT |
| `xcbeautify` | Homebrew-resolved | Format Xcode build output | MIT |

`Brewfile` declares these tools. The repository does not lock Homebrew formula
versions, so a clean build is toolchain-reproducible by policy rather than by a
complete binary lockfile.

## Updating the toolchain

1. Review the new macOS and Xcode requirement.
2. Update `project.yml`, documentation, and CI together.
3. Regenerate `Cadence.xcodeproj`.
4. Run `scripts/verify.sh`.
5. Manually check playback routes and the affected interface on macOS.
