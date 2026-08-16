# Privacy

Last updated: August 16, 2026

Cadence is a local macOS music player and library manager. It does not include
an account system, analytics, advertising, telemetry, or crash-reporting
service. Its optional Remote Media feature uses a network client only after you
choose and configure WebDAV or Google Drive in Settings.

## Data Cadence handles

Cadence can read audio, artwork, metadata, and LRC files you select or drop into
the app. After you confirm an import, it copies managed media into:

```text
~/Music/Cadence
```

The managed folder can contain audio, artwork, lyrics, import manifests,
SwiftData records, and recoverable Trash data. Cadence also stores interface and
playback preferences through macOS preferences.

## Optional Remote Media

Remote Media is disconnected by default. After you explicitly connect a
provider, Cadence reads its library manifest and downloads or prefetches remote
audio needed for playback. Downloaded audio is SHA-256-verified and kept in a
bounded local cache. Cadence does not upload your local managed library merely
because a provider is connected.

For WebDAV, Cadence stores the selected server URL and username in its local
settings and stores the password in Keychain. WebDAV connections require HTTPS,
except for loopback addresses used for local development. For Google Drive,
Cadence starts the OAuth flow in the system browser and requests the
`https://www.googleapis.com/auth/drive.file` scope. The OAuth authorization
state is stored in Keychain; the configured folder, manifest, client, redirect
URL, and cache budget stay in local settings.

Disconnecting removes the configured provider and its Keychain credential or
OAuth state. Existing remote-media cache files are local to your Mac and are
not automatically deleted by Disconnect; remove Cadence's cache through macOS
after quitting the app if you also want to erase downloaded remote audio.

## Data not sent to QenTerra

Cadence does not transmit your managed library or listening data to Nikita
Melnychenko (QenTerra), iCloud, or an analytics service. When you connect Remote
Media, Cadence transmits only the requests, credentials, OAuth data, and remote
media data necessary to use the provider you selected.
The app opens a URL in your default browser only after you select a GitHub,
Wiki, or license link in Settings.

## Files you import

Cadence leaves the selected source files unchanged. Its managed copies remain
under your control. Removing an item from Cadence moves the managed data to the
library's recoverable Trash; emptying that Trash permanently removes those
managed copies.

## macOS permissions

Cadence uses App Sandbox. It requests read access for files and folders you
select and Music folder access for the managed library. macOS controls these
permissions.

## Your choices

You can:

- delete or restore managed items from Cadence Trash;
- empty Cadence Trash;
- remove `~/Music/Cadence` after quitting the app to delete the managed
  library;
- reset Cadence preferences through macOS or by removing the app's preference
  data;
- disconnect Remote Media to remove the provider configuration and its Keychain
  credential or OAuth state; and
- delete the local Remote Media cache after quitting Cadence when you no longer
  want downloaded remote audio on the Mac.

Back up music you care about before deleting the library folder. Cadence's
managed library is not a substitute for a backup.

## Changes

Any future remote provider, library synchronization behavior, or telemetry must
update this document before release.

Questions can be opened in the
[Cadence repository](https://github.com/QenTerra/cadence/issues) without
including private media or metadata.
