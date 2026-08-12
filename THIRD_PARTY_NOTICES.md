# Third-party notices

Cadence includes the following Swift Package Manager runtime dependencies:

| Package | Version | Role | License | Source |
| --- | --- | --- | --- | --- |
| QenTerraDesignTokens | Local QDS `1.12.x` | Shared visual tokens | MIT | QenTerra design system |
| GRDB.swift | `7.10.0` | Derived lyrics full-text index | MIT | [groue/GRDB.swift](https://github.com/groue/GRDB.swift) |
| AppAuth | `2.1.0` | Google Drive OAuth 2.0 flow | Apache-2.0 | [openid/AppAuth-iOS](https://github.com/openid/AppAuth-iOS) |
| Sparkle | `2.9.5` | Signed in-app software updates | MIT | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) |

Their complete license texts and copyright notices remain available in their
linked source distributions. Cadence does not modify or relicense them.

## Apple frameworks

Cadence links frameworks supplied by Xcode and macOS, including SwiftUI,
AppKit, Foundation, Observation, SwiftData, AVFoundation, AVFAudio, CoreAudio,
AudioToolbox, CoreImage, MediaPlayer, and UniformTypeIdentifiers. Apple provides
these components under the terms that accompany Xcode, the macOS SDK, and
macOS. Cadence does not relicense them.

## Development tools

The following tools help generate, format, lint, build, and test Cadence. They
are not bundled in the app:

| Tool | Role | License | Source |
| --- | --- | --- | --- |
| XcodeGen | Generate `Cadence.xcodeproj` | MIT | [yonaskolb/XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| SwiftFormat | Formatting checks | MIT | [nicklockwood/SwiftFormat](https://github.com/nicklockwood/SwiftFormat) |
| SwiftLint | Static style checks | MIT | [realm/SwiftLint](https://github.com/realm/SwiftLint) |
| xcbeautify | Format `xcodebuild` output | MIT | [cpisciotta/xcbeautify](https://github.com/cpisciotta/xcbeautify) |

Homebrew resolves the installed versions from `Brewfile`. Xcode is installed
separately from Apple.

## Imported media

Audio, artwork, metadata, and lyrics imported by a user are not part of
Cadence's source distribution. Their copyright and license remain with their
respective owners.
