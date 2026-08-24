import Foundation

enum LibraryAvailability: Equatable, Sendable {
    case empty
    case loading
    case ready
    case failed(LibraryStoreFailure)
}

struct LibraryStoreFailure: Equatable, Sendable {
    let message: String
}

enum LibraryContentLoadState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(LibraryStoreFailure)

    var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    var failure: LibraryStoreFailure? {
        if case let .failed(failure) = self {
            return failure
        }
        return nil
    }
}

struct ProductionSmartCollectionSummary: Sendable {
    let count: Int
    let totalDuration: TimeInterval

    static let empty = ProductionSmartCollectionSummary(
        count: 0,
        totalDuration: 0
    )

    var isEmpty: Bool {
        count < 1
    }
}

struct ProductionSmartCollectionStoreResult: Sendable {
    let evaluation: ProductionSmartCollectionEvaluation
    var tracks: [LibraryTrackProjection]
    var nextOffset: Int?
    var contentVersion: TrackTableContentVersion
}

struct ProductionTrackTableSource: Sendable {
    let tracks: [LibraryTrackProjection]
    let contentVersion: TrackTableContentVersion
}

struct LibraryArtworkPublicationPayload: Equatable, Sendable {
    let tracksByID: [UUID: LibraryTrackProjection]
    let albumsByID: [UUID: LibraryAlbumProjection]
    let artistsByID: [UUID: LibraryArtistProjection]
    let playlistsByID: [UUID: LibraryPlaylistProjection]

    static let empty = LibraryArtworkPublicationPayload(
        tracksByID: [:],
        albumsByID: [:],
        artistsByID: [:],
        playlistsByID: [:]
    )
}

struct LibraryArtworkPublication: Equatable, Sendable {
    let epoch: UInt64
    let generation: UInt64
    let effects: [ManagedArtworkPublicationEffect]
    let payload: LibraryArtworkPublicationPayload

    var tracksByID: [UUID: LibraryTrackProjection] {
        payload.tracksByID
    }

    var albumsByID: [UUID: LibraryAlbumProjection] {
        payload.albumsByID
    }

    var artistsByID: [UUID: LibraryArtistProjection] {
        payload.artistsByID
    }

    var playlistsByID: [UUID: LibraryPlaylistProjection] {
        payload.playlistsByID
    }

    @discardableResult
    func mergeTracks(into rows: inout [LibraryTrackProjection]) -> Bool {
        var changed = false
        for index in rows.indices {
            guard
                let replacement = tracksByID[rows[index].id],
                replacement != rows[index]
            else {
                continue
            }
            rows[index] = replacement
            changed = true
        }
        return changed
    }

    func mergingAlbums(
        in sections: ArtistReleaseSections
    ) -> ArtistReleaseSections {
        ArtistReleaseSections(
            singles: mergingAlbums(in: sections.singles),
            eps: mergingAlbums(in: sections.eps),
            albums: mergingAlbums(in: sections.albums),
            appearsOn: mergingAlbums(in: sections.appearsOn)
        )
    }

    func mergingAlbums(
        in rows: [LibraryAlbumProjection]
    ) -> [LibraryAlbumProjection] {
        rows.map { albumsByID[$0.id] ?? $0 }
    }
}

enum LyricsSearchIndexState: Equatable, Sendable {
    case unavailable
    case idle
    case indexing
    case ready
    case failed(String)
}

enum LibraryStoreMode: Equatable, Sendable {
    case unavailable
    case production
    case trackPageFixture
    case playlistFixture
    case catalogLookupFixture
}

enum LibraryStoreAccessError: Error, Equatable, LocalizedError, Sendable {
    case repositoryUnavailable

    var errorDescription: String? {
        String(
            localized: "The managed library is unavailable. Import music or reopen the library, then try again."
        )
    }
}

struct LibraryStoreContext: Sendable {
    let epoch: UInt64
    let repository: LibraryRepository?
}

struct ArtworkMetadataResultEntry {
    let epoch: UInt64
    let artwork: ManagedArtworkProjection?
}

struct ArtworkMetadataResultCache {
    private let countLimit: Int
    private var entries: [UUID: ArtworkMetadataResultEntry] = [:]
    private var insertionOrder: [UUID] = []

    init(countLimit: Int = 256) {
        self.countLimit = max(countLimit, 1)
    }

    var count: Int {
        entries.count
    }

    var insertionOrderedIDs: [UUID] {
        insertionOrder
    }

    func result(
        id: UUID,
        epoch: UInt64
    ) -> ArtworkMetadataResultEntry? {
        guard let entry = entries[id], entry.epoch == epoch else {
            return nil
        }
        return entry
    }

    mutating func insert(_ entry: ArtworkMetadataResultEntry, id: UUID) {
        if entries[id] == nil {
            insertionOrder.append(id)
        }
        entries[id] = entry
        while entries.count > countLimit {
            let evictedID = insertionOrder.removeFirst()
            entries[evictedID] = nil
        }
    }

    mutating func invalidate(id: UUID) {
        entries[id] = nil
        insertionOrder.removeAll { $0 == id }
    }

    mutating func removeAll() {
        entries.removeAll()
        insertionOrder.removeAll()
    }
}
