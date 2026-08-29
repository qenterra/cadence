# Development

## Requirements

Apple silicon Mac with macOS 26 or later for use; full Xcode and the declared development tools for source verification.

## Setup

```sh
git clone https://github.com/QenTerra/cadence.git
cd cadence
bash scripts/verify.sh
```

## Common workflow

```sh
git switch -c qenterra/<short-kebab-purpose>
bash scripts/verify.sh
git diff --check
```

`scripts/verify.sh` regenerates the Xcode project from `project.yml`, validates the release contract and installer artwork, runs SwiftFormat and SwiftLint, executes the Xcode test suite, checks localisation and Periphery debt, and inspects the built application. It writes disposable build state only under `.build/`; remove that directory to clean the checkout.

## Configuration and secrets

Development configuration is versioned in `project.yml`, `.swiftformat`, `.swiftlint.yml`, `Brewfile`, and `requirements-dev.txt`. Keep Developer ID credentials, notarisation credentials, local library contents, and user data outside the repository.

## Generated source

`Cadence.xcodeproj` is generated from `project.yml` by XcodeGen and remains committed so ordinary Xcode use is predictable. `scripts/verify.sh` regenerates it before testing and catches drift. Build products, reports, Python environments, module caches, and release staging remain external or under ignored `.build/` state and are never committed.

For a public repository, put agent instructions, assistant scratch work, prompts, transcripts, skill bundles, caches, local environments, logs, coverage, test output, and temporary build state in an isolated temporary directory outside the checkout. These paths are prohibited even when ignored. Commit consumer-facing generated output only when `.github/qenterra-repository.json` declares it under `published_artifacts` with a separate source path, a `schemaVersion: 1` JSON manifest covering every source and artifact file by SHA-256 and strict integer byte count, an existing Git-tracked `scripts/` verifier, and a concrete regeneration trigger. A source without a readable Git index leaves tracking `Unverified`. The static audit never executes that command; run it separately in an isolated temporary checkout before publication.

## Debugging

Use synthetic fixtures in `Tests/` and sanitise file paths, library metadata, lyrics, and service responses before sharing diagnostics. Prefer the focused test target that reproduces a failure, then run the complete gate before publication. Do not commit temporary logging or weaken a failing assertion to conceal the defect.
