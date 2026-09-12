# Building from Source

Cadence 1.0.0 (build 3) is available as an ad-hoc signed, non-notarized
[manual download](Getting-Started). Building from source requires an Apple
silicon Mac, macOS 26 or later, Xcode 27 or later, Homebrew, and Git.

## Setup

```sh
git clone https://github.com/QenTerra/cadence.git
cd cadence
brew bundle
./scripts/prepare_python_tools.sh
xcodegen generate --spec project.yml
open Cadence.xcodeproj
```

Follow the current [dependency instructions](https://github.com/QenTerra/cadence/blob/main/docs/DEPENDENCIES.md)
before generating the project. Cadence consumes Swift packages for shared
QenTerra components and algorithms, database access, OAuth, and updates; it is
not dependency-free. The release uses an immutable Design System dependency.

Select the **Cadence** scheme and **My Mac**. Set `DEVELOPER_DIR` for the current
shell if Xcode is installed at a non-default path.

## Verify

```sh
bash scripts/verify.sh
git diff --check
```

The complete gate covers project generation, formatting, linting, localization,
dependency ownership, the Xcode build and tests, and release contracts. A hosted
static-check pass alone does not prove an Xcode 27 build or native UI acceptance.
See the [build guide](https://github.com/QenTerra/cadence/blob/main/docs/BUILDING.md)
and [testing guide](https://github.com/QenTerra/cadence/blob/main/docs/TESTING.md)
for toolchain requirements, screenshot generation, and local installer checks.

Keep build output, credentials, signing material, real-library media, and
screenshots containing personal information out of commits. Use the isolated
synthetic screenshot fixture for public images.

For publication, follow [Release Process](Release-Process).
