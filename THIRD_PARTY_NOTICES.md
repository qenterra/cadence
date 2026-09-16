# Third-party notices

Current Cadence source builds include the following Swift Package Manager
runtime dependencies:

| Package | Version | Role | License | Source |
| --- | --- | --- | --- | --- |
| QenTerra Design System | `1.0.2` | Shared foundations, audio analysis, design tokens, components, and media presentation | MIT | [QenTerra/design-system](https://github.com/QenTerra/design-system) |
| GRDB.swift | `7.11.1` | Derived lyrics full-text index and catalog-migration validation | MIT | [groue/GRDB.swift](https://github.com/groue/GRDB.swift) |
| AppAuth | `3.0.0` | Google Drive OAuth 2.0 flow | Apache-2.0 | [openid/AppAuth-iOS](https://github.com/openid/AppAuth-iOS) |
| Sparkle | `2.9.6` | Signed in-app software updates | MIT | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) |

Verbatim license texts and required notices are stored in
`Sources/Cadence/Resources/ThirdPartyLicenses` and are copied into source-built
app bundles. Cadence does not modify or relicense these dependencies.

The published Cadence 1.0.0 source tag and binary pin QenTerra Design System
`2.0.0`; the other three package versions match the table above. Use the
`Package.resolved` file at a release tag as the authority for that release.
The published `1.0.0` downloads predate the bundled-license correction and do
not contain these files; correct this in the next release instead of silently
replacing an existing release asset.

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
| Periphery | Detect unreachable Swift declarations | MIT | [peripheryapp/periphery](https://github.com/peripheryapp/periphery) |
| Python | Run release tooling | Python-2.0 | [Python Software Foundation](https://www.python.org/) |
| Pillow `12.3.0` | Validate release artwork and PNG metadata | HPND | [python-pillow/Pillow](https://github.com/python-pillow/Pillow) |
| ds_store `1.3.3` | Write deterministic Finder metadata for release disk images | MIT | [dmgbuild/ds_store](https://github.com/dmgbuild/ds_store) |
| mac_alias `2.2.3` | Write the Applications alias in release disk images | MIT | [dmgbuild/mac_alias](https://github.com/dmgbuild/mac_alias) |
| dmgbuild `1.6.7` | Build disk images on the documented compatibility path | MIT | [dmgbuild documentation](https://dmgbuild.readthedocs.io/) |

Homebrew resolves the installed formula versions from `Brewfile`;
`requirements-dev.txt` pins Pillow, and `release/requirements.txt` pins the
disk-image libraries. Xcode is installed separately from Apple.

## Imported media

Audio, artwork, metadata, and lyrics imported by a user are not part of
Cadence's source distribution. Their copyright and license remain with their
respective owners.
