# Cadence

Cadence is a native macOS player and manager for local lossless music libraries.

## Development stack

- Swift 6 with SwiftUI
- SwiftData for the local library model
- AVFoundation for playback and audio inspection
- CloudKit for a later iCloud sync layer
- XcodeGen, SwiftFormat, SwiftLint, and Swift Testing for local development

The production app now owns a versioned SwiftData library and a real
Empty → Scanning → Review → Importing → Complete workflow. Folder selection and whole-window file/folder drops scan
without writing, then a confirmed import copies verified originals into `~/Music/Cadence.library` under stable UUID
filenames. Same-folder matching LRC files are linked, exact duplicates are excluded, possible duplicates remain a
user choice, and durable manifests recover or roll back interrupted imports.

The production library now plays imported assets through one canonical `PlaybackCoordinator`. Supported stereo
lossless files use an `AVAudioEngine`/PCM path with conservative compatible-next scheduling; native playback preserves
system handling for multichannel, spatial, AirPlay, and unsupported PCM formats. The bottom player, Now Playing,
line-level LRC timing, editable queue, quality profiles, media keys, and Control Center all consume the same playback
state. Audio Path reports the source, selected backend, route, and whether the next transition is gapless-capable
without relabelling ordinary spatialized stereo as Dolby Atmos.

Some editor and browsing surfaces remain preview-backed while their durable SwiftData edit paths are migrated. Live
hardware acceptance for gapless playback, output-route changes, AirPlay, and verified Atmos assets remains explicit
work; Graph is not part of the active product.

## Requirements

- macOS 26 or newer
- Xcode 27 beta or newer
- Homebrew tools: `xcodegen`, `swiftformat`, `swiftlint`, and `xcbeautify`

Select Xcode once if command-line tools still point at the standalone Command Line Tools package. Replace the path if you keep Xcode somewhere else:

```zsh
sudo xcode-select -s "/Applications/Coding/Xcode.app/Contents/Developer"
sudo xcodebuild -license accept
```

## Verify locally

```zsh
bash scripts/verify.sh
```

The command generates `Cadence.xcodeproj`, checks formatting and linting, and runs the macOS test target. Open the generated project in Xcode:

```zsh
open Cadence.xcodeproj
```

## Project structure

```text
Sources/Cadence/
  App/          # observable application state
  Components/   # shared SwiftUI interface components
  DesignSystem/ # monochrome theme and platform compatibility
  Features/     # library, listening, tags, smart collections, import, and shell
  Foundation/   # app-wide configuration and infrastructure
  Import/       # scan, review, transactional copy, manifests, and recovery
  ManagedLibrary/ # Cadence.library paths and package layout
  Models/       # immutable UI and preview values
  Playback/     # coordinator, PCM/native backends, routing, and system media
  Persistence/  # SwiftData schema, records, repository, and paged store
Tests/CadenceTests/
  # unit and integration coverage
```

Cadence targets macOS 26 and newer. The interface uses native Liquid Glass APIs directly, with an opaque
accessibility-safe surface when Reduce Transparency is enabled.
