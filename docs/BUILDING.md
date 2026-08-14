# Building from source

Cadence currently ships as source. The repository does not provide a signed or
notarized application.

## Requirements

- Apple silicon Mac
- macOS 26 or later
- Xcode 27 or later with a compatible macOS SDK
- Homebrew
- Git
- A sibling `design-system` checkout containing `packages/swift`

## Clone

```sh
git clone https://github.com/QenTerra/cadence.git
git clone <authorized-design-system-source> design-system
cd cadence
```

Keep `cadence` and `design-system` in the same parent directory. The design
system is not downloaded implicitly; use the authorized QenTerra source for
your environment.

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

This installs XcodeGen, SwiftFormat, SwiftLint, and xcbeautify. Xcode resolves
the local QDS Swift package from `../design-system/packages/swift`.

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

The script regenerates the project, runs the QDS consumer doctor, checks
formatting and linting, builds the app, runs unit and integration tests, and
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
archive, change `appcast.xml`, or produce anything suitable for publication.
The public mode and its required Developer ID/notarization inputs are documented
in [Software updates](UPDATES.md).

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
