# Cadence

Cadence is a native macOS player and manager for local lossless music libraries.

## Development stack

- Swift 6 with SwiftUI
- SwiftData for the local library model
- AVFoundation for playback and audio inspection
- CloudKit for a later iCloud sync layer
- XcodeGen, SwiftFormat, SwiftLint, and Swift Testing for local development

The current product slice implements three connected mock-data workspaces: the Column Library
(Artists → Albums → Tracks), Tags taxonomy (Tag Groups → Tags → Tracks or Albums), and playback-first Smart
Collections. Tags supports native-style multi-selection, direct and inherited tag controls, deterministic suggestions
that require explicit acceptance, and system Undo/Redo. Smart Collections opens as a listening page with deterministic
album-art mosaics, sortable tracks, Play and Shuffle queue snapshots, and a read-only rule summary. `Edit Rules`
replaces the listening region with the nested Boolean editor while the Collections list remains stable. Drafts stay
isolated until Save, and dirty mode or destination changes require Save, Discard, or Cancel. All workspaces share track
selection, search, and the compact full-width player.

The editor and playback queue currently mutate preview state in memory. Import, persistence, metadata writing, and
real AVFoundation playback remain intentionally deferred.

## Requirements

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
  Features/     # library, tags, smart collections, and app shell
  Foundation/   # app-wide configuration and infrastructure
  Models/       # immutable preview models and mock data
Tests/CadenceTests/
  # unit and integration coverage
```

The interface uses system components and materials on macOS 15, then adopts Liquid Glass automatically on macOS 26 and
newer where the platform API is available.
