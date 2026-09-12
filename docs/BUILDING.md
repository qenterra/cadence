# Building from source

Cadence 1.0.0 is available as an ad-hoc signed, non-notarized manual download.
See [installation](../README.md#install-cadence) for the DMG and Gatekeeper
instructions. This page covers building and verifying the source.

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
./scripts/prepare_python_tools.sh
```

This installs XcodeGen, SwiftFormat, SwiftLint, and xcbeautify. All Cadence UI
presentation and shared algorithms come from QenTerra Design System. The
release pins Design System 2.0.0 through Swift Package Manager; no sibling
checkout is required. The ownership check fetches the same locked commit into
an ignored local cache. See [Dependencies](DEPENDENCIES.md).

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
app, runs unit and integration tests, and
rejects `Localizable.xcstrings` when it no longer matches compiler-extracted
SwiftUI and Foundation strings.

To regenerate the public screenshots from the isolated production-backed test
fixture:

```sh
bash scripts/update_screenshots.sh
```

The harness uses an in-memory SwiftData repository, synthetic metadata, fixed
window contracts, and never opens `~/Music/Cadence`. It writes a full
System/Light/Dark viewport matrix to a sandbox candidate directory and promotes
the set only after all captures succeed. Review every changed PNG under
`docs/images/` before committing it.

## Validate the installer locally

```sh
CADENCE_RELEASE_MODE=local bash scripts/prepare_release.sh
```

The local mode produces an ad-hoc signed DMG under `.build/releases/local` for
layout and mount/copy/launch checks. It intentionally does not create a Sparkle
archive, change `appcast.xml`, or constitute a verified public release.
The 1.0.0 manual distribution and the separate Developer ID/notarization
workflow are documented in [Software updates](UPDATES.md).

GitHub Actions runs project generation, SwiftFormat, and SwiftLint. The hosted
macOS image currently provides Xcode 26.6, which cannot build this Xcode 27
project. Run the complete gate locally until the hosted image includes a
compatible toolchain.

## Local-only paths

Do not commit:

- `.build/`, DerivedData, or other build output;
- `xcuserdata` or user schemes;
- certificates, profiles, private keys, or signing exports;
- `~/Music/Cadence` or any imported audio, artwork, or lyrics;
- screenshots containing a real library or personal filesystem paths.
