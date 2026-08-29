# Testing

## Complete gate

```sh
bash scripts/verify.sh
```

The gate regenerates the Xcode project, validates release metadata and DMG imagery, runs SwiftFormat and SwiftLint debt checks, executes the unit and integration suite, verifies localisation and Periphery findings, and inspects the built app bundle and asset catalogue.

## Test layers

| Layer | Purpose | Command | Evidence limit |
| --- | --- | --- | --- |
| Unit | Models, stores, coordinators, import, playback, and release tooling | `bash scripts/verify.sh` | Does not prove prolonged playback or real libraries |
| Integration | SwiftData, managed-library, provider, and application boundaries | `bash scripts/verify.sh` | Uses controlled fixtures and the selected macOS/Xcode environment |
| Built product | Bundle metadata, document roles, icons, and appearance assets | `bash scripts/verify.sh` | Does not prove signed installation or notarisation |
| Manual | Audio hardware, VoiceOver, appearance, updater, and clean-machine install | Release checklist in `docs/RELEASING.md` | Requires current human and device evidence |

## Fixtures

Use synthetic, deterministic fixtures. Do not read personal data, live user libraries, production credentials, or mutable external resources unless a separately authorised acceptance test requires them.

## Failures and flaky tests

Reproduce before repair, preserve the failing evidence, identify whether the environment or product failed, and never weaken assertions to make a gate green.
