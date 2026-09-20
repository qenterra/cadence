# Architecture

Cadence separates SwiftUI presentation, application coordination, the managed-library file boundary, SwiftData persistence, and playback services. Detailed and version-specific engineering documentation remains in [`docs/ARCHITECTURE.md`](https://github.com/QenTerra/cadence/blob/main/docs/ARCHITECTURE.md).

## Components

| Component | Responsibility | Boundary |
| --- | --- | --- |
| SwiftUI features and components | Present library, playback, metadata, lyrics, and settings | Main-actor view state and explicit user actions |
| Managed library and import pipeline | Copy, index, recover, and remove user-selected media | User-authorized managed Cadence folder |
| Persistence | SwiftData catalog, GRDB lyrics search, and catalog-migration integrity checks | Sandboxed Application Support; never a removable-media database |
| Playback | Coordinate local and temporary external audio | AVFoundation, output routes, and media controls |

## Shared packages

QenTerraDesignTokens, QenTerraComponents, and QenTerraMediaComponents provide
reusable presentation. QenTerraFoundation and QenTerraAudioAnalysis provide
shared algorithms without UI dependencies. Cadence owns library models,
application state, import policy, artwork loading, table coordination, and
playback behavior.

## Decisions

Maintained architectural decisions belong under [`docs/decisions/`](https://github.com/QenTerra/cadence/tree/main/docs/decisions); temporary implementation plans do not belong in the Wiki.
