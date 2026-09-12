# Troubleshooting

## Gatekeeper blocks the first launch

Cadence 1.0.0 is ad-hoc signed, not Developer ID signed, and not notarized.
Download the DMG from the [official release](https://github.com/QenTerra/cadence/releases/tag/v1.0.0)
and compare its SHA-256 with the attached checksums. If you trust that download,
use Cadence's **Open Anyway** option in **System Settings > Privacy & Security**
after the blocked launch. See [Apple's instructions](https://support.apple.com/en-gb/102445).
If macOS instead reports malware or a damaged app, stop and report the exact
message and asset checksum.

## Check for Updates does not offer 1.0.0

This release requires a manual download. It does not change the Sparkle feed.
Quit Cadence, install the official DMG into Applications, and reopen the app.

## Source-build problems

Start with the full verification command:

```sh
bash scripts/verify.sh
```

It catches missing tools, project-generation drift, formatting and lint issues,
build failures, and test failures.

## Full Xcode was not found

Command Line Tools alone cannot build Cadence. Point the current shell at a full
Xcode installation:

```sh
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
xcodebuild -version
```

## A Homebrew tool is missing

```sh
brew bundle
```

Do not add similarly named binaries to the repository.

## The generated project changed

`project.yml` is authoritative:

```sh
xcodegen generate --spec project.yml
git diff -- Cadence.xcodeproj
```

Commit the generated project when the change is expected.

## Cadence cannot create its library

Confirm that macOS allows Cadence to access the Music folder and that
`~/Music` is writable. Do not disable App Sandbox or add broad filesystem
entitlements as a shortcut.

## Files do not appear in Import Review

- Confirm the file uses a supported audio extension.
- Drop the file or containing folder again.
- Check whether Cadence classified it as an exact or possible duplicate.
- Keep the audio and `.lrc` in the same folder with matching normalized
  basenames when automatic lyric linking is expected.

Inspection does not copy files. Cadence writes only after confirmation.

## Playback is silent or chooses another backend

- Open Now Playing and inspect **Audio Path**.
- Check the current output route.
- Verify that the managed file still exists.
- Try the built-in Mac output before testing Bluetooth, AirPlay, multichannel,
  or spatial routes.

Do not label spatialized stereo as Dolby Atmos. Cadence reports the source and
route capabilities it can verify.

## Lyrics do not follow playback

Confirm that the linked LRC contains line timestamps such as `[01:23.45]`.
Plain text can be edited, but it cannot follow playback until its lines have
timestamps.

## A deleted item needs to come back

Open Cadence Trash and use Restore. Empty Trash removes managed copies and
their restore manifest. It does not delete the original files that were
imported from another folder.

## Reporting a problem

Follow [CONTRIBUTING.md](../CONTRIBUTING.md). Remove personal media, metadata,
paths, artwork, and lyrics from the report. Use [SECURITY.md](../SECURITY.md)
for vulnerabilities.
