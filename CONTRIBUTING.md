# Contributing

Cadence accepts focused bug fixes, tests, documentation corrections, and
well-scoped improvements.

## Before opening an issue

1. Search existing issues.
2. Reproduce the problem on macOS 26 or later.
3. Remove personal library paths, filenames, artwork, lyrics, and metadata from
   screenshots and logs.
4. Include the Cadence version, macOS version, Mac model, output device, file
   format, and exact reproduction steps when they matter.

Do not attach copyrighted audio or lyrics. A small file you created yourself is
the safest playback fixture.

## Development setup

```sh
git clone https://github.com/QenTerra/cadence.git
cd cadence
brew bundle
xcodegen generate --spec project.yml
open Cadence.xcodeproj
```

Edit `project.yml` instead of hand-editing project configuration. Regenerate
`Cadence.xcodeproj` after project changes.

## Required checks

```sh
bash scripts/verify.sh
git diff --check
```

The script generates the project, checks SwiftFormat and SwiftLint, builds the
app, and runs the test target.

GitHub Actions runs the project-generation, SwiftFormat, and SwiftLint portion.
Its hosted macOS image currently provides Xcode 26.6; contributors must run the
complete build and test gate locally with Xcode 27.

Playback glitches, AirPlay, Bluetooth route changes, spatial audio, gapless
transitions, media keys, reduced motion, VoiceOver, and large real libraries
still need manual acceptance on relevant hardware.

## Pull requests

- Keep one problem per pull request.
- Add a regression test when the behavior can be tested without hardware.
- Explain any data migration or managed-file change.
- Update public documentation when behavior, requirements, dependencies, or
  privacy changes.
- Do not commit DerivedData, `.build`, local libraries, imported media,
  credentials, private keys, provisioning profiles, or personal screenshots.

By contributing, you agree that your contribution is licensed under the
repository's MIT License.
