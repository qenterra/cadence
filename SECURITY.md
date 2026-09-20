# Security

## Supported version

Cadence `1.0.1` is the current public release. Security fixes target the
current `main` branch. The release is ad-hoc signed and not notarized.

## Report a vulnerability

Use GitHub's private vulnerability reporting for
[QenTerra/cadence](https://github.com/QenTerra/cadence/security/advisories/new).
Do not open a public issue or email exploit details, private media,
credentials, logs, or identifying paths. If the private form is unavailable,
retain the report privately until the route is restored.

Include:

- the affected commit or version;
- macOS and Mac architecture;
- reproduction steps;
- the expected impact;
- a minimal synthetic fixture, when one is required.

Remove usernames, home-directory paths, library filenames, artwork, lyrics,
signing data, tokens, certificates, and unrelated system logs.

## Security boundaries

Cadence:

- runs inside App Sandbox;
- copies confirmed imports into a managed package;
- uses staged import and manifests so interrupted work can recover or roll back;
- resolves managed paths inside the `Cadence` library folder;
- keeps Trash restore information with the deleted managed item;
- verifies software-update metadata and downloads through Sparkle; and
- does not include an analytics SDK or embedded web view.

Do not weaken sandbox entitlements, path containment, duplicate validation,
managed-file rollback, or SwiftData migration checks to work around a local
problem.

## Secrets and private data

The repository must not contain credentials, signing identities, provisioning
profiles, private keys, personal music libraries, imported media, or real
library screenshots. Report an accidental disclosure privately before
attempting public cleanup.
