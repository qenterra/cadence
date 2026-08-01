import Foundation
import Observation
import SwiftData

enum LibraryAvailability: Equatable, Sendable {
    case empty
    case loading
    case ready
    case failed(LibraryStoreFailure)
}

struct LibraryStoreFailure: Equatable, Sendable {
    let message: String
}

private struct InitialLibrarySnapshot: Sendable {
    let tracks: LibraryPage<LibraryTrackProjection>
    let artists: LibraryPage<LibraryArtistProjection>
    let albums: LibraryPage<LibraryAlbumProjection>
    let tags: LibraryPage<LibraryTagProjection>
    let counts: LibraryCatalogCounts
    let trashOperations: [LibraryTrashProjection]
}

@MainActor
@Observable
final class LibraryStore {
    private(set) var repository: LibraryRepository?
    private(set) var lyricsService: ManagedLyricsService?
    private var trackCursor: LibraryPageCursor?
    private var catalogSearchGeneration = 0
    private var playbackQueueProjectionGeneration = 0
    @ObservationIgnored var artworkAssetCache: [UUID: ArtworkAsset] = [:]
    var artistCursor: LibraryPageCursor?
    var albumCursor: LibraryPageCursor?

    var availability: LibraryAvailability
    private(set) var tracks: [LibraryTrackProjection] = []
    private(set) var playbackQueueTracks: [PlaybackQueueTrackProjection] = []
    private(set) var isLoadingPlaybackQueueTracks = false
    private(set) var playbackQueueProjectionError: LibraryStoreFailure?
    var artists: [LibraryArtistProjection] = []
    var albums: [LibraryAlbumProjection] = []
    var tags: [LibraryTagProjection] = []
    var playlists: [LibraryPlaylistProjection] = []
    private(set) var smartCollectionIndex =
        ProductionSmartCollectionIndex.empty
    private(set) var isLoadingSmartCollectionIndex = false
    var selectedPlaylistID: UUID?
    var selectedPlaylistTracks: [LibraryTrackProjection] = []
    var tagRevision = 0
    var trashOperations: [LibraryTrashProjection] = []
    private(set) var catalogCounts = LibraryCatalogCounts.empty
    private(set) var catalogSearchQuery = ""
    private(set) var catalogSearchResults = CatalogSearchResults.empty
    private(set) var isCatalogSearching = false
    private(set) var searchQuery = ""

    init(
        container: ModelContainer? = nil,
        package: ManagedLibraryPackage? = nil
    ) {
        if let container {
            let repository = LibraryRepository(modelContainer: container)
            self.repository = repository
            lyricsService = package.map {
                ManagedLyricsService(
                    package: $0,
                    repository: repository
                )
            }
            availability = .ready
        } else {
            repository = nil
            lyricsService = nil
            availability = .empty
        }
    }

    var canLoadMoreTracks: Bool {
        trackCursor != nil
    }

    var canLoadMoreArtists: Bool {
        artistCursor != nil
    }

    var canLoadMoreAlbums: Bool {
        albumCursor != nil
    }

    func attach(
        repository: LibraryRepository,
        package: ManagedLibraryPackage? = nil
    ) {
        self.repository = repository
        lyricsService = package.map {
            ManagedLyricsService(
                package: $0,
                repository: repository
            )
        }
        availability = .ready
    }

    func loadInitialLibrary() async {
        guard let repository else {
            resetLibrary(availability: .empty)
            return
        }

        availability = .loading
        do {
            try await apply(initialSnapshot(from: repository))
        } catch {
            resetLibrary(
                availability: .failed(
                    LibraryStoreFailure(message: error.localizedDescription)
                )
            )
        }
    }

    func searchCatalog(_ query: String) async {
        catalogSearchGeneration += 1
        let generation = catalogSearchGeneration
        catalogSearchQuery = query

        guard let repository else {
            catalogSearchResults = .empty
            isCatalogSearching = false
            return
        }
        guard !SearchNormalizer.normalize(query).isEmpty else {
            catalogSearchResults = .empty
            isCatalogSearching = false
            return
        }

        isCatalogSearching = true
        do {
            let results = try await repository.catalogSearch(query: query)
            guard generation == catalogSearchGeneration else {
                return
            }
            catalogSearchResults = results
            isCatalogSearching = false
        } catch {
            guard generation == catalogSearchGeneration else {
                return
            }
            catalogSearchResults = .empty
            isCatalogSearching = false
            availability = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
        }
    }

    func clearCatalogSearch() {
        catalogSearchGeneration += 1
        catalogSearchQuery = ""
        catalogSearchResults = .empty
        isCatalogSearching = false
    }

    func restoreCatalogSearch(_ query: String) {
        catalogSearchGeneration += 1
        catalogSearchQuery = query
        catalogSearchResults = .empty
        isCatalogSearching = false

        guard
            repository != nil,
            !SearchNormalizer.normalize(query).isEmpty
        else {
            return
        }
        Task {
            await searchCatalog(query)
        }
    }

    func artist(id: UUID) async -> LibraryArtistProjection? {
        try? await repository?.artist(id: id)
    }

    func album(id: UUID) async -> LibraryAlbumProjection? {
        try? await repository?.album(id: id)
    }

    func tracks(albumID: UUID) async -> [LibraryTrackProjection] {
        await (
            try? repository?.albumTracksInPlaybackOrder(
                albumID: albumID
            )
        ) ?? []
    }

    func tracks(artistID: UUID) async -> [LibraryTrackProjection] {
        await (try? repository?.tracks(artistID: artistID).items) ?? []
    }

    func albums(artistID: UUID) async -> [LibraryAlbumProjection] {
        await (try? repository?.albums(artistID: artistID)) ?? []
    }

    func tracks(tagID: UUID) async -> [LibraryTrackProjection] {
        await (try? repository?.tracks(tagID: tagID).items) ?? []
    }

    func allTrackIDs() async -> [UUID] {
        await (try? repository?.allTrackIDs()) ?? tracks.map(\.id)
    }

    func loadPlaybackQueueTracks(
        ids: [UUID]
    ) async {
        playbackQueueProjectionGeneration += 1
        let generation = playbackQueueProjectionGeneration

        guard !ids.isEmpty else {
            playbackQueueTracks = []
            playbackQueueProjectionError = nil
            isLoadingPlaybackQueueTracks = false
            return
        }

        let currentByID = Dictionary(
            playbackQueueTracks.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        playbackQueueTracks = ids.map { id in
            currentByID[id] ?? PlaybackQueueTrackProjection(
                id: id,
                state: .loading
            )
        }
        playbackQueueProjectionError = nil

        guard let repository else {
            playbackQueueTracks = ids.map {
                PlaybackQueueTrackProjection(id: $0, state: .unavailable)
            }
            isLoadingPlaybackQueueTracks = false
            return
        }

        isLoadingPlaybackQueueTracks = true
        do {
            let projections = try await repository.playbackQueueTracks(
                ids: ids
            )
            guard generation == playbackQueueProjectionGeneration else {
                return
            }
            playbackQueueTracks = projections
            isLoadingPlaybackQueueTracks = false
        } catch {
            guard generation == playbackQueueProjectionGeneration else {
                return
            }
            let message = error.localizedDescription
            playbackQueueTracks = ids.map { id in
                if let current = currentByID[id], current.track != nil {
                    current
                } else {
                    PlaybackQueueTrackProjection(
                        id: id,
                        state: .failed(message)
                    )
                }
            }
            playbackQueueProjectionError = LibraryStoreFailure(
                message: message
            )
            isLoadingPlaybackQueueTracks = false
        }
    }

    func loadSmartCollectionIndex() async {
        guard let repository else {
            smartCollectionIndex = .empty
            return
        }
        isLoadingSmartCollectionIndex = true
        defer {
            isLoadingSmartCollectionIndex = false
        }
        do {
            smartCollectionIndex =
                try await repository.productionSmartCollectionIndex()
        } catch {
            availability = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
        }
    }

    func loadInitialTracks() async {
        await replaceTracks(search: searchQuery)
    }

    func searchTracks(_ query: String) async {
        searchQuery = query
        await replaceTracks(search: query)
    }

    func loadNextTracks() async {
        guard let repository, let trackCursor else {
            return
        }

        availability = .loading
        do {
            let page = try await repository.tracksPage(
                after: trackCursor,
                search: searchQuery
            )
            tracks.append(contentsOf: page.items)
            self.trackCursor = page.nextCursor
            availability = .ready
        } catch {
            availability = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
        }
    }

    func replaceTracks(search: String) async {
        guard let repository else {
            tracks = []
            trackCursor = nil
            availability = .empty
            return
        }

        availability = .loading
        do {
            let page = try await repository.tracksPage(search: search)
            tracks = page.items
            trackCursor = page.nextCursor
            availability = .ready
        } catch {
            tracks = []
            trackCursor = nil
            availability = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
        }
    }

    func showImportedTracks(
        importID: UUID
    ) async {
        guard let repository else {
            return
        }
        availability = .loading
        do {
            tracks = try await repository.importedTracks(
                importID: importID
            )
            trackCursor = nil
            searchQuery = ""
            availability = .ready
        } catch {
            tracks = []
            trackCursor = nil
            availability = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
        }
    }
}

private extension LibraryStore {
    func initialSnapshot(
        from repository: LibraryRepository
    ) async throws -> InitialLibrarySnapshot {
        async let tracks = repository.tracksPage()
        async let artists = repository.artistsPage()
        async let albums = repository.albumsPage()
        async let tags = repository.tagsPage()
        async let counts = repository.catalogCounts()
        async let trash = repository.trashOperations()
        return try await InitialLibrarySnapshot(
            tracks: tracks,
            artists: artists,
            albums: albums,
            tags: tags,
            counts: counts,
            trashOperations: trash
        )
    }

    func apply(_ snapshot: InitialLibrarySnapshot) {
        tracks = snapshot.tracks.items
        trackCursor = snapshot.tracks.nextCursor
        artists = snapshot.artists.items
        artistCursor = snapshot.artists.nextCursor
        albums = snapshot.albums.items
        albumCursor = snapshot.albums.nextCursor
        tags = snapshot.tags.items
        catalogCounts = snapshot.counts
        trashOperations = snapshot.trashOperations
        availability = .ready
    }

    func resetLibrary(availability: LibraryAvailability) {
        tracks = []
        artists = []
        albums = []
        tags = []
        trashOperations = []
        catalogCounts = .empty
        catalogSearchResults = .empty
        trackCursor = nil
        artistCursor = nil
        albumCursor = nil
        self.availability = availability
    }
}
