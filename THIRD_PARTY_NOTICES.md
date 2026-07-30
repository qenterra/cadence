# Third-party notices

Cadence does not bundle a third-party runtime library or package dependency.

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
