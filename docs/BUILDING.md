# Building from source

Cadence currently ships as source. The repository does not provide a signed or
notarized application.

## Requirements

- Apple silicon Mac
- macOS 26 or later
- Xcode 27 or later with a compatible macOS SDK
- Homebrew
- Git

## Clone

```sh
git clone https://github.com/QenTerra/cadence.git
cd cadence
```

## Select Xcode

The verification script uses `DEVELOPER_DIR` when set, then checks the active
`xcode-select` path and common Xcode locations.

For the current shell:

```sh
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
xcodebuild -version
```

Change the path when your Xcode app has another name or location.

## Install development tools

```sh
brew bundle
```

This installs XcodeGen, SwiftFormat, SwiftLint, and xcbeautify. Cadence has no
external package or binary runtime dependency.

## Generate and open the project

```sh
xcodegen generate --spec project.yml
open Cadence.xcodeproj
```

Select the `Cadence` scheme and run on **My Mac**.

## Verify

```sh
bash scripts/verify.sh
git diff --check
```

The script regenerates the project, checks formatting and linting, builds the
app, and runs unit and integration tests.

To regenerate the public screenshots from the isolated production-backed test
fixture:

```sh
bash scripts/update_screenshots.sh
```

The harness uses an in-memory SwiftData repository, synthetic metadata, a
fixed 1080 × 876 point Dark appearance, and never opens `~/Music/Cadence.library`.
Review the four PNG files under `docs/images/` before committing them.

GitHub Actions runs project generation, SwiftFormat, and SwiftLint. The hosted
macOS image currently provides Xcode 26.6, which cannot build this Xcode 27
project. Run the complete gate locally until the hosted image includes a
compatible toolchain.

## Local-only paths

Do not commit:

- `.build/`, DerivedData, or other build output;
- `xcuserdata` or user schemes;
- certificates, profiles, private keys, or signing exports;
- `~/Music/Cadence.library` or any imported audio, artwork, or lyrics;
- screenshots containing a real library or personal filesystem paths.
