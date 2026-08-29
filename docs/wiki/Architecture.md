# Architecture

Cadence separates SwiftUI presentation, application coordination, the managed-library file boundary, SwiftData persistence, playback services, and optional remote providers. Detailed and version-specific engineering documentation remains in [`docs/ARCHITECTURE.md`](https://github.com/QenTerra/cadence/blob/main/docs/ARCHITECTURE.md).

## Components

| Component | Responsibility | Boundary |
| --- | --- | --- |
| SwiftUI features and components | Present library, playback, metadata, lyrics, and settings | Main-actor view state and explicit user actions |
| Managed library and import pipeline | Copy, index, recover, and remove user-selected media | User-authorised `Cadence.library` folder |
| Persistence | Store catalogue and derived search state | Sandboxed Application Support; never a removable-media database |
| Playback | Coordinate local and temporary external audio | AVFoundation, output routes, and media controls |
| Providers | Resolve explicitly requested external metadata or media | Network boundary with provider-specific policy |

## Decisions

Maintained architectural decisions belong under [`docs/decisions/`](https://github.com/QenTerra/cadence/tree/main/docs/decisions); temporary implementation plans do not belong in the Wiki.
