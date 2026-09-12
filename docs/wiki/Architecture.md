# Architecture

Cadence separates SwiftUI presentation, application coordination, the managed-library file boundary, SwiftData persistence, playback services, and optional remote providers. Detailed and version-specific engineering documentation remains in [`docs/ARCHITECTURE.md`](https://github.com/QenTerra/cadence/blob/main/docs/ARCHITECTURE.md).

## Components

| Component | Responsibility | Boundary |
| --- | --- | --- |
| SwiftUI features and components | Present library, playback, metadata, lyrics, and settings | Main-actor view state and explicit user actions |
| Managed library and import pipeline | Copy, index, recover, and remove user-selected media | User-authorised managed Cadence folder |
| Persistence | SwiftData catalog, GRDB lyrics search, and catalog-migration integrity checks | Sandboxed Application Support; never a removable-media database |
| Playback | Coordinate local and temporary external audio | AVFoundation, output routes, and media controls |
| Providers | Resolve explicitly requested external metadata or media | Network boundary with provider-specific policy |

## Shared packages

QenTerraDesignTokens, QenTerraComponents, and QenTerraMediaComponents provide
reusable presentation. QenTerraFoundation and QenTerraAudioAnalysis provide
shared algorithms without UI dependencies. Cadence owns library models,
application state, import policy, artwork loading, table coordination, and
playback behavior.

WebDAV and Google Drive providers expose read-only manifest and media access.
Remote playback uses a bounded local cache and verifies downloaded objects
before handing local files to the audio backends.

## Decisions

Maintained architectural decisions belong under [`docs/decisions/`](https://github.com/QenTerra/cadence/tree/main/docs/decisions); temporary implementation plans do not belong in the Wiki.
