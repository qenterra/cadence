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

typealias LibraryTrackPageLoader = @Sendable (
    _ query: LibraryTrackQuery,
    _ cursor: LibraryPageCursor?
) async throws -> LibraryPage<LibraryTrackProjection>

@MainActor
@Observable
final class LibraryStore {
    private(set) var repository: LibraryRepository?
    private(set) var lyricsService: ManagedLyricsService?
    var trackCursor: LibraryPageCursor?
    var trackRequestGeneration = 0
    private var catalogSearchGeneration = 0
    @ObservationIgnored var trackPageLoader: LibraryTrackPageLoader?
    @ObservationIgnored var artworkAssetCache: [UUID: ArtworkAsset] = [:]
    var artistCursor: LibraryPageCursor?
    var albumCursor: LibraryPageCursor?

    var availability: LibraryAvailability
    var tracks: [LibraryTrackProjection] = []
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
    var searchQuery = ""
    var trackQuery = LibraryTrackQuery.allTracks
    var isLoadingNextTracks = false
    var browserArtistID: UUID?
    var browserAlbums: [LibraryAlbumProjection] = []
    var browserAlbumID: UUID?
    var browserTracks: [LibraryTrackProjection] = []
    var browserTrackSort = LibraryTrackSort.titleAscending
    var isLoadingNextBrowserAlbums = false
    var isLoadingNextBrowserTracks = false
    @ObservationIgnored var browserAlbumCursor: LibraryPageCursor?
    @ObservationIgnored var browserTrackCursor: LibraryPageCursor?
    @ObservationIgnored var browserAlbumGeneration = 0
    @ObservationIgnored var browserTrackGeneration = 0

    init(
        container: ModelContainer? = nil,
        package: ManagedLibraryPackage? = nil
    ) {
        if let container {
            let repository = LibraryRepository(modelContainer: container)
            self.repository = repository
            trackPageLoader = { query, cursor in
                try await repository.tracksPage(
                    query: query,
                    after: cursor
                )
            }
            lyricsService = package.map {
                ManagedLyricsService(
                    package: $0,
                    repository: repository
                )
            }
            availability = .ready
        } else {
            repository = nil
            trackPageLoader = nil
            lyricsService = nil
            availability = .empty
        }
    }

    init(trackPageLoader: @escaping LibraryTrackPageLoader) {
        repository = nil
        lyricsService = nil
        self.trackPageLoader = trackPageLoader
        availability = .ready
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
        trackPageLoader = { query, cursor in
            try await repository.tracksPage(
                query: query,
                after: cursor
            )
        }
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
        guard let repository else {
            return []
        }
        var tracks: [LibraryTrackProjection] = []
        var cursor: LibraryPageCursor?
        do {
            repeat {
                let page = try await repository.tracksPage(
                    query: LibraryTrackQuery(scope: .artist(artistID)),
                    after: cursor
                )
                tracks.append(contentsOf: page.items)
                cursor = page.nextCursor
            } while cursor != nil
            return deduplicatedTracks(tracks)
        } catch {
            return []
        }
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
        trackRequestGeneration += 1
        tracks = snapshot.tracks.items
        trackCursor = snapshot.tracks.nextCursor
        trackQuery = .allTracks
        searchQuery = ""
        isLoadingNextTracks = false
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
        trackRequestGeneration += 1
        tracks = []
        artists = []
        albums = []
        tags = []
        trashOperations = []
        catalogCounts = .empty
        catalogSearchResults = .empty
        trackCursor = nil
        trackQuery = .allTracks
        searchQuery = ""
        isLoadingNextTracks = false
        artistCursor = nil
        albumCursor = nil
        self.availability = availability
    }
}
