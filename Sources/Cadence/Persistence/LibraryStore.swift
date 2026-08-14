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

@MainActor
@Observable
final class LibraryStore {
    var mode: LibraryStoreMode
    var repository: LibraryRepository?
    var lyricsService: ManagedLyricsService?
    var artworkService: ManagedArtworkService?
    @ObservationIgnored var lyricsSearchIndexer: LyricsSearchIndexer?
    var trackCursor: LibraryPageCursor?
    var trackRequestGeneration = 0
    var tagCursor: LibraryPageCursor?
    var tagGeneration = 0
    var isLoadingNextTags = false
    var catalogSearchGeneration = 0
    @ObservationIgnored var playbackQueueProjectionGeneration = 0
    @ObservationIgnored var trackPageLoader: LibraryTrackPageLoader?
    @ObservationIgnored var playlistClient: LibraryPlaylistClient?
    @ObservationIgnored var catalogLookupClient: LibraryCatalogLookupClient?
    @ObservationIgnored var allTracksWindow: LibraryTrackWindow?
    @ObservationIgnored let artworkAssetCache = ArtworkAssetCache()
    @ObservationIgnored var artworkDataLoads: [ArtworkAssetCache.Key: Task<Data, Error>] = [:]
    var artistCursor: LibraryPageCursor?
    var albumCursor: LibraryPageCursor?
    var isLoadingNextArtists = false
    var isLoadingNextAlbums = false
    var favoriteTrackCursor: LibraryPageCursor?
    var favoriteArtistCursor: LibraryPageCursor?
    var favoriteAlbumCursor: LibraryPageCursor?
    var isLoadingNextFavoriteTracks = false
    var isLoadingNextFavoriteArtists = false
    var isLoadingNextFavoriteAlbums = false

    var availability: LibraryAvailability
    var tracks: [LibraryTrackProjection] = []
    var favoriteTracks: [LibraryTrackProjection] = []
    var favoriteTrackIDs: Set<UUID> = []
    var recentlyPlayedTracks: [LibraryTrackProjection] = []
    var playbackQueueTracks: [PlaybackQueueTrackProjection] = []
    var isLoadingPlaybackQueueTracks = false
    var playbackQueueProjectionError: LibraryStoreFailure?
    var artists: [LibraryArtistProjection] = []
    var favoriteArtists: [LibraryArtistProjection] = []
    var albums: [LibraryAlbumProjection] = []
    var favoriteAlbums: [LibraryAlbumProjection] = []
    var tags: [LibraryTagProjection] = []
    var playlists: [LibraryPlaylistProjection] = []
    var playlistListState = LibraryContentLoadState.idle
    var smartCollectionRuleData =
        ProductionSmartCollectionRuleData.empty
    var smartCollectionSummaries:
        [SmartCollectionRuleGroup: ProductionSmartCollectionSummary] = [:]
    var smartCollectionResults:
        [SmartCollectionRuleGroup: ProductionSmartCollectionStoreResult] = [:]
    var smartCollectionRuleDataGeneration = 0
    var smartCollectionSummaryGeneration = 0
    var smartCollectionResultGeneration = 0
    var isLoadingNextSmartCollectionResult = false
    var isLoadingSmartCollectionData = false
    var selectedPlaylistID: UUID?
    var selectedPlaylistTracks: [LibraryTrackProjection] = []
    var selectedPlaylistTracksState = LibraryContentLoadState.idle
    var tagRevision = 0
    var trashOperations: [LibraryTrashProjection] = []
    var catalogCounts = LibraryCatalogCounts.empty
    private(set) var catalogSearchQuery = ""
    var catalogSearchResults = CatalogSearchResults.empty
    private(set) var isCatalogSearching = false
    var loadingCatalogSearchGroups: Set<CatalogSearchGroup> = []
    var operationFailure: LibraryOperationFailure?
    var lyricsSearchIndexState = LyricsSearchIndexState.unavailable
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
            mode = .production
            let repository = LibraryRepository(modelContainer: container)
            self.repository = repository
            playlistClient = LibraryPlaylistClient(repository: repository)
            catalogLookupClient = LibraryCatalogLookupClient(
                repository: repository
            )
            trackPageLoader = { query, cursor in
                try await repository.tracksPage(
                    query: query,
                    after: cursor
                )
            }
            allTracksWindow = LibraryTrackWindow { query, offset, limit in
                try await repository.tracksWindow(
                    query: query,
                    offset: offset,
                    limit: limit
                )
            }
            lyricsService = package.map {
                ManagedLyricsService(
                    package: $0,
                    repository: repository
                )
            }
            artworkService = package.map {
                ManagedArtworkService(
                    package: $0,
                    repository: repository
                )
            }
            availability = .ready
            configureLyricsSearch(package: package, repository: repository)
        } else {
            mode = .unavailable
            repository = nil
            playlistClient = nil
            catalogLookupClient = nil
            trackPageLoader = nil
            allTracksWindow = nil
            lyricsService = nil
            artworkService = nil
            lyricsSearchIndexer = nil
            availability = .empty
        }
    }

    init(trackPageLoader: @escaping LibraryTrackPageLoader) {
        mode = .trackPageFixture
        repository = nil
        playlistClient = nil
        catalogLookupClient = nil
        lyricsService = nil
        self.trackPageLoader = trackPageLoader
        allTracksWindow = nil
        availability = .ready
    }

    init(playlistClient: LibraryPlaylistClient) {
        mode = .playlistFixture
        repository = nil
        self.playlistClient = playlistClient
        catalogLookupClient = nil
        trackPageLoader = nil
        allTracksWindow = nil
        availability = .ready
    }

    init(catalogLookupClient: LibraryCatalogLookupClient) {
        mode = .catalogLookupFixture
        repository = nil
        playlistClient = nil
        self.catalogLookupClient = catalogLookupClient
        trackPageLoader = nil
        allTracksWindow = nil
        availability = .ready
    }

    var canLoadMoreTracks: Bool {
        trackCursor != nil
    }

    /// Repository-backed features use this boundary instead of interpreting
    /// missing production dependencies as a successful empty result.
    func requireRepository() throws -> LibraryRepository {
        guard mode == .production, let repository else {
            throw LibraryStoreAccessError.repositoryUnavailable
        }
        return repository
    }

    var canLoadMoreArtists: Bool {
        artistCursor != nil
    }

    var canLoadMoreAlbums: Bool {
        albumCursor != nil
    }

    var canLoadMoreTags: Bool {
        tagCursor != nil
    }

    func searchCatalog(_ query: String) async {
        catalogSearchGeneration += 1
        let generation = catalogSearchGeneration
        catalogSearchQuery = query

        guard !SearchNormalizer.normalize(query).isEmpty else {
            catalogSearchResults = .empty
            isCatalogSearching = false
            return
        }

        isCatalogSearching = true
        do {
            let repository = try requireRepository()
            async let catalog = repository.catalogSearch(query: query)
            async let lyricMatches = lyricsCatalogResults(
                query: query,
                limit: 40
            )
            var results = try await catalog
            results.lyrics = await lyricMatches
            guard generation == catalogSearchGeneration else {
                return
            }
            catalogSearchResults = results
            isCatalogSearching = false
        } catch {
            guard generation == catalogSearchGeneration else {
                return
            }
            isCatalogSearching = false
            recordOperationFailure(
                .catalogSearch,
                error: error
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
            mode == .production,
            !SearchNormalizer.normalize(query).isEmpty
        else {
            return
        }
        Task {
            await searchCatalog(query)
        }
    }
}
