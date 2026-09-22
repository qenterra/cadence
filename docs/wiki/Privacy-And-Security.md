# Privacy and Security

Cadence is local-first. It has no Cadence account system, analytics,
advertising, telemetry, or crash-reporting service. The authoritative policy is
[Privacy](https://github.com/QenTerra/cadence/blob/main/PRIVACY.md).

## Local data

Confirmed imports copy media into the selected managed Cadence folder, whose
default location is `~/Music/Cadence`. Audio, artwork, lyrics, manifests, and
recoverable Trash live there. The SwiftData catalog and derived lyrics-search
index remain in sandboxed Application Support. Preferences use macOS settings
storage. Importing leaves the selected source files unchanged.

Cadence does not send your managed library or listening activity to QenTerra or
an analytics service. Project links open in your browser when selected.

## File access and deletion

Cadence uses App Sandbox and macOS access grants for selected files and the
managed Music folder. Managed paths must remain inside the chosen folder.
Imports and Trash operations use manifests and recovery; conflicting restore
destinations are reported.

Use **Restore** or **Empty Trash** for managed items. **Delete Entire Library**
removes the managed folder and its local Application Support catalog. Back up
both stores before deleting or moving library data.

## Release identity

Cadence 1.0.2 is ad-hoc signed, not Developer ID signed, and not
notarized. Initial installation is manual; existing installations can verify
and install 1.0.2 through the EdDSA-signed Sparkle feed.
See [Getting Started](Getting-Started) for official downloads, checksums, and
Gatekeeper instructions.

Report vulnerabilities through
[GitHub private vulnerability reporting](https://github.com/QenTerra/cadence/security/advisories/new).
Do not include credentials, private media, personal paths, unrelated logs, or
vulnerability details in public issues or email.
