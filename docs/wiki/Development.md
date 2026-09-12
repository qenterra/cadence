# Development

## Setup

```sh
git clone https://github.com/QenTerra/cadence.git
cd cadence
brew bundle
./scripts/prepare_python_tools.sh
xcodegen generate --spec project.yml
open Cadence.xcodeproj
```

Use Xcode 27 or later. Resolve the Design System dependency described in the
[build guide](https://github.com/QenTerra/cadence/blob/main/docs/BUILDING.md)
before generating the project.

## Verify

```sh
bash scripts/verify.sh
```

Read the canonical [development guide](https://github.com/QenTerra/cadence/blob/main/docs/DEVELOPMENT.md), [testing guide](https://github.com/QenTerra/cadence/blob/main/docs/TESTING.md), and [contribution policy](https://github.com/QenTerra/cadence/blob/main/CONTRIBUTING.md).
