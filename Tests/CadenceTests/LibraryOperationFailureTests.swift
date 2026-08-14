@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibraryOperationFailureTests {
    @Test("Store modes make unavailable and production repositories explicit")
    func repositoryModesAreExplicit() throws {
        let unavailable = LibraryStore()
        #expect(unavailable.mode == .unavailable)

        let container = try LibraryContainerFactory.inMemory()
        let production = LibraryStore(container: container)
        #expect(production.mode == .production)
    }

    @Test("Unavailable tag operations fail instead of returning empty success")
    func unavailableTagOperationsFail() async {
        let store = LibraryStore()
        let tagID = UUID()
        let trackID = UUID()

        await #expect(throws: LibraryStoreAccessError.repositoryUnavailable) {
            try await store.tracksForTagPicker()
        }
        await #expect(throws: LibraryStoreAccessError.repositoryUnavailable) {
            try await store.tagStates(trackID: trackID)
        }
        await #expect(throws: LibraryStoreAccessError.repositoryUnavailable) {
            try await store.assignTag(tagID, trackIDs: [trackID])
        }
    }

    @Test("Quick tag and Now Playing helpers publish operation failures")
    func tagPresentationFailuresArePublished() async {
        let store = LibraryStore()
        let tagID = UUID()
        let trackID = UUID()

        await store.assignTagReportingFailure(tagID, trackIDs: [trackID])
        #expect(store.operationFailure?.operation == .tagMutation)

        store.dismissOperationFailure()
        let states = await store.tagStatesReportingFailure(trackID: trackID)
        #expect(states == nil)
        #expect(store.operationFailure?.operation == .tagLoad)
    }

    @Test("Lyrics absence and service failure remain distinct")
    func unavailableLyricsServiceThrows() async {
        let store = LibraryStore()

        await #expect(throws: ManagedLyricsServiceError.unavailable) {
            try await store.lyricsDocument(trackID: UUID())
        }
    }

    @Test("Artwork editing cannot hide a failed owner snapshot")
    func artworkSnapshotFailurePropagates() async throws {
        let container = try LibraryContainerFactory.inMemory()
        let repository = LibraryRepository(modelContainer: container)
        let location = ManagedLibraryLocation(
            musicDirectory: FileManager.default.temporaryDirectory
        )
        let store = LibraryStore()
        store.artworkService = ManagedArtworkService(
            package: ManagedLibraryPackage(location: location),
            repository: repository
        )
        let request = ManagedArtworkEditRequest(
            ownerKind: .album,
            ownerID: UUID(),
            data: Data(),
            scale: 1,
            normalizedOffset: .zero
        )

        await #expect(throws: LibraryStoreAccessError.repositoryUnavailable) {
            try await store.setArtwork(request, location: location)
        }
    }

    @Test("A failed replacement keeps the last valid track page")
    func failedTrackReplacementPreservesData() async {
        let seededTrack = LibraryTrackProjection(
            id: UUID(),
            title: "Still Here",
            artistID: nil,
            artist: "Artist",
            albumID: nil,
            album: "Album",
            duration: 180,
            year: 2026,
            codec: "flac",
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            isFavorite: false,
            customArtworkID: nil,
            artworkID: nil,
            relativeMediaPath: "Media/still-here.flac",
            lastPlayedAt: nil,
            hasSynchronizedLyrics: false
        )
        let loader = FailingTrackPageLoader(track: seededTrack)
        let store = LibraryStore { query, cursor in
            try await loader.load(query: query, cursor: cursor)
        }

        await store.loadInitialTracks()
        await store.searchTracks("fails")

        #expect(store.tracks == [seededTrack])
        #expect(store.availability == .ready)
        #expect(store.operationFailure?.operation == .trackPage)

        await store.retryOperationFailure()

        #expect(store.tracks == [seededTrack])
        #expect(store.operationFailure == nil)
    }

    @Test("Playlist mutations report failure instead of pretending to succeed")
    func playlistMutationFailuresAreExplicit() async {
        let playlistID = UUID()
        let trackID = UUID()

        let createStore = LibraryStore(
            playlistClient: .failing(at: .create)
        )
        await createStore.createPlaylist(name: "Road Trip")
        #expect(createStore.operationFailure?.operation == .playlistCreate)

        let renameStore = LibraryStore(
            playlistClient: .failing(at: .rename)
        )
        renameStore.selectedPlaylistID = playlistID
        await renameStore.renameSelectedPlaylist(to: "Night Drive")
        #expect(renameStore.operationFailure?.operation == .playlistRename)

        let deleteStore = LibraryStore(
            playlistClient: .failing(at: .delete)
        )
        deleteStore.selectedPlaylistID = playlistID
        await deleteStore.deleteSelectedPlaylist()
        #expect(deleteStore.selectedPlaylistID == playlistID)
        #expect(deleteStore.operationFailure?.operation == .playlistDelete)

        let addStore = LibraryStore(
            playlistClient: .failing(at: .add)
        )
        await addStore.addToPlaylist(
            playlistID: playlistID,
            trackIDs: [trackID]
        )
        #expect(addStore.operationFailure?.operation == .playlistAdd)

        let removeStore = LibraryStore(
            playlistClient: .failing(at: .remove)
        )
        removeStore.selectedPlaylistID = playlistID
        await removeStore.removeFromSelectedPlaylist(trackIDs: [trackID])
        #expect(removeStore.operationFailure?.operation == .playlistRemove)

        let reorderStore = LibraryStore(
            playlistClient: .failing(at: .reorder)
        )
        reorderStore.selectedPlaylistID = playlistID
        await reorderStore.reorderSelectedPlaylist(trackIDs: [trackID])
        #expect(reorderStore.operationFailure?.operation == .playlistReorder)
    }

    @Test("Playlist load failure preserves content and cannot look empty")
    func playlistLoadFailurePreservesContent() async {
        let playlist = LibraryPlaylistProjection(
            id: UUID(),
            name: "Keep Me",
            trackCount: 2,
            totalDuration: 360,
            modifiedAt: .now,
            customArtworkID: nil
        )
        let store = LibraryStore(
            playlistClient: .failing(at: .list)
        )
        store.playlists = [playlist]

        await store.loadPlaylists()

        #expect(store.playlists == [playlist])
        #expect(store.playlistListState.isFailure)
        #expect(store.operationFailure?.operation == .playlistList)
    }

    @Test("Catalog lookups distinguish missing content from storage failure")
    func catalogLookupFailureIsNotAnEmptyResult() async throws {
        let itemID = UUID()
        let emptyStore = LibraryStore(catalogLookupClient: .empty)

        #expect(try await emptyStore.album(id: itemID) == nil)
        #expect(try await emptyStore.artist(id: itemID) == nil)
        #expect(try await emptyStore.tracks(albumID: itemID).isEmpty)
        #expect(try await emptyStore.tracks(artistID: itemID).isEmpty)
        #expect(try await emptyStore.allTrackIDs().isEmpty)

        let failingStore = LibraryStore(catalogLookupClient: .failing)
        await #expect(throws: CatalogLookupFailure.expected) {
            try await failingStore.album(id: itemID)
        }
        await #expect(throws: CatalogLookupFailure.expected) {
            try await failingStore.artist(id: itemID)
        }
        await #expect(throws: CatalogLookupFailure.expected) {
            try await failingStore.tracks(albumID: itemID)
        }
        await #expect(throws: CatalogLookupFailure.expected) {
            try await failingStore.tracks(artistID: itemID)
        }
        await #expect(throws: CatalogLookupFailure.expected) {
            try await failingStore.allTrackIDs()
        }
    }
}

private extension LibraryCatalogLookupClient {
    static let empty = Self(
        artist: { _ in nil },
        album: { _ in nil },
        albumTracks: { _ in [] },
        artistTracks: { _ in [] },
        artistAlbums: { _ in [] },
        artistReleases: { _ in .empty },
        tagTracks: { _ in [] },
        allTrackIDs: { [] }
    )

    static let failing = Self(
        artist: { _ in throw CatalogLookupFailure.expected },
        album: { _ in throw CatalogLookupFailure.expected },
        albumTracks: { _ in throw CatalogLookupFailure.expected },
        artistTracks: { _ in throw CatalogLookupFailure.expected },
        artistAlbums: { _ in throw CatalogLookupFailure.expected },
        artistReleases: { _ in throw CatalogLookupFailure.expected },
        tagTracks: { _ in throw CatalogLookupFailure.expected },
        allTrackIDs: { throw CatalogLookupFailure.expected }
    )
}

private enum CatalogLookupFailure: Error {
    case expected
}

private enum PlaylistFailurePoint: Equatable {
    case list
    case tracks
    case create
    case rename
    case delete
    case add
    case remove
    case reorder
    case albumTracks
    case artistTracks
}

private extension LibraryPlaylistClient {
    static func failing(
        at failurePoint: PlaylistFailurePoint
    ) -> Self {
        Self(
            playlists: {
                try fail(.list, requested: failurePoint)
                return []
            },
            playlistTracks: { _ in
                try fail(.tracks, requested: failurePoint)
                return []
            },
            create: { _ in
                try fail(.create, requested: failurePoint)
                throw PlaylistFailure.expected
            },
            rename: { _, _ in
                try fail(.rename, requested: failurePoint)
            },
            delete: { _ in
                try fail(.delete, requested: failurePoint)
            },
            add: { _, _ in
                try fail(.add, requested: failurePoint)
            },
            remove: { _, _ in
                try fail(.remove, requested: failurePoint)
            },
            reorder: { _, _ in
                try fail(.reorder, requested: failurePoint)
            },
            albumTrackIDs: { _ in
                try fail(.albumTracks, requested: failurePoint)
                return []
            },
            artistTrackIDs: { _ in
                try fail(.artistTracks, requested: failurePoint)
                return []
            }
        )
    }

    static func fail(
        _ operation: PlaylistFailurePoint,
        requested failurePoint: PlaylistFailurePoint
    ) throws {
        if operation == failurePoint {
            throw PlaylistFailure.expected
        }
    }
}

private enum PlaylistFailure: Error {
    case expected
}

private actor FailingTrackPageLoader {
    let track: LibraryTrackProjection
    var requestCount = 0

    init(track: LibraryTrackProjection) {
        self.track = track
    }

    func load(
        query _: LibraryTrackQuery,
        cursor _: LibraryPageCursor?
    ) throws -> LibraryPage<LibraryTrackProjection> {
        requestCount += 1
        if requestCount == 2 {
            throw Failure.expected
        }
        return LibraryPage(items: [track], nextCursor: nil)
    }

    private enum Failure: Error {
        case expected
    }
}
