# Privacy and Security

Cadence is local-first. It has no Cadence account system, analytics,
advertising, telemetry, or crash-reporting service. Optional Remote Media uses
network access after you choose and configure WebDAV or Google Drive in
Settings. The authoritative policy is [Privacy](https://github.com/QenTerra/cadence/blob/main/PRIVACY.md).

## Local data

Confirmed imports copy media into the selected managed Cadence folder, whose
default location is `~/Music/Cadence`. Audio, artwork, lyrics, manifests, and
recoverable Trash live there. The SwiftData catalog and derived lyrics-search
index remain in sandboxed Application Support. Preferences use macOS settings
storage. Importing leaves the selected source files unchanged.

Cadence does not send your managed library or listening activity to QenTerra or
an analytics service. Project links open in your browser when selected.

## Remote Media

Remote providers are disconnected by default. Connecting a provider permits
manifest reads and media downloads or prefetches needed for playback. Downloaded
audio is hash-verified and stored in a bounded cache. Connecting does not upload
your local library.

WebDAV uses HTTPS, except loopback development addresses; its password is stored
in Keychain. Google Drive uses browser OAuth with the `drive.file` scope and
stores authorization state in Keychain. Provider configuration stays local.
Disconnecting removes configuration and credentials, but does not automatically
erase downloaded cache files. See the privacy policy for removal details.

## File access and deletion

Cadence uses App Sandbox and macOS access grants for selected files and the
managed Music folder. Managed paths must remain inside the chosen folder.
Imports and Trash operations use manifests and recovery; conflicting restore
destinations are reported.

Use **Restore** or **Empty Trash** for managed items. **Delete Entire Library**
removes the managed folder and its local Application Support catalog. Back up
both stores before deleting or moving library data.

## Release identity

Cadence 1.0.0 (build 3) is ad-hoc signed, not Developer ID signed, and not
notarized. It is a manual download, with no Sparkle update for this version.
See [Getting Started](Getting-Started) for official downloads, checksums, and
Gatekeeper instructions.

Report vulnerabilities through [private vulnerability reporting](https://github.com/QenTerra/cadence/security/advisories/new).
Do not include credentials, private media, personal paths, or unrelated logs in
public issues.
