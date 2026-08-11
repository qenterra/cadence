# Security

## Supported version

Cadence is a source-only development project. Security fixes target the current
`main` branch.

## Report a vulnerability

Use GitHub's private vulnerability reporting for
[QenTerra/cadence](https://github.com/QenTerra/cadence/security/advisories/new).
If that form is unavailable, open a minimal issue asking for a private contact
route. Do not publish exploit details or private media.

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
- resolves managed paths inside `Cadence.library`;
- keeps Trash restore information with the deleted managed item;
- connects to WebDAV or Google Drive only after explicit Remote Media setup;
- keeps WebDAV credentials and Google OAuth state in Keychain; and
- does not include an analytics SDK or embedded web view.

Do not weaken sandbox entitlements, path containment, duplicate validation,
managed-file rollback, or SwiftData migration checks to work around a local
problem.

## Secrets and private data

The repository must not contain credentials, signing identities, provisioning
profiles, private keys, personal music libraries, imported media, or real
library screenshots. Report an accidental disclosure privately before
attempting public cleanup.
