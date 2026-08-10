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
    let favoriteTracks: LibraryPage<LibraryTrackProjection>
    let favoriteTrackIDs: [UUID]
    let recentlyPlayedTracks: [LibraryTrackProjection]
    let artists: LibraryPage<LibraryArtistProjection>
    let favoriteArtists: LibraryPage<LibraryArtistProjection>
    let albums: LibraryPage<LibraryAlbumProjection>
    let favoriteAlbums: LibraryPage<LibraryAlbumProjection>
    let tags: LibraryPage<LibraryTagProjection>
    let counts: LibraryCatalogCounts
    let trashOperations: [LibraryTrashProjection]
}

typealias LibraryTrackPageLoader = @Sendable (
    _ query: LibraryTrackQuery,
    _ cursor: LibraryPageCursor?
) async throws -> LibraryPage<LibraryTrackProjection>

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

@MainActor
@Observable
final class LibraryStore {
    private(set) var repository: LibraryRepository?
    private(set) var lyricsService: ManagedLyricsService?
    private(set) var artworkService: ManagedArtworkService?
    @ObservationIgnored var lyricsSearchIndexer: LyricsSearchIndexer?
    var trackCursor: LibraryPageCursor?
    var trackRequestGeneration = 0
    var tagCursor: LibraryPageCursor?
    var tagGeneration = 0
    var isLoadingNextTags = false
    var catalogSearchGeneration = 0
    @ObservationIgnored var playbackQueueProjectionGeneration = 0
    @ObservationIgnored var trackPageLoader: LibraryTrackPageLoader?
    @ObservationIgnored var allTracksWindow: LibraryTrackWindow?
    @ObservationIgnored let artworkAssetCache = ArtworkAssetCache()
    @ObservationIgnored var artworkDataLoads: [ArtworkAssetCache.Key: Task<Data?, Never>] = [:]
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
    var tagRevision = 0
    var trashOperations: [LibraryTrashProjection] = []
    private(set) var catalogCounts = LibraryCatalogCounts.empty
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
            let repository = LibraryRepository(modelContainer: container)
            self.repository = repository
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
            repository = nil
            trackPageLoader = nil
            allTracksWindow = nil
            lyricsService = nil
            artworkService = nil
            lyricsSearchIndexer = nil
            availability = .empty
        }
    }

    init(trackPageLoader: @escaping LibraryTrackPageLoader) {
        repository = nil
        lyricsService = nil
        self.trackPageLoader = trackPageLoader
        allTracksWindow = nil
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

    var canLoadMoreTags: Bool {
        tagCursor != nil
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
        configureLyricsSearch(package: package, repository: repository)
        availability = .ready
    }

    func detach() {
        repository = nil
        trackPageLoader = nil
        allTracksWindow = nil
        lyricsService = nil
        artworkService = nil
        lyricsSearchIndexer = nil
        artworkDataLoads.values.forEach { $0.cancel() }
        artworkDataLoads.removeAll()
        lyricsSearchIndexState = .unavailable
        resetLibrary(availability: .empty)
    }

    func loadInitialLibrary() async {
        guard let repository else {
            resetLibrary(availability: .empty)
            return
        }

        availability = .loading
        do {
            try await apply(initialSnapshot(from: repository))
            await synchronizeLyricsSearch()
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
            repository != nil,
            !SearchNormalizer.normalize(query).isEmpty
        else {
            return
        }
        Task {
            await searchCatalog(query)
        }
    }
}

private extension LibraryStore {
    func configureLyricsSearch(
        package: ManagedLibraryPackage?,
        repository: LibraryRepository
    ) {
        guard let package else {
            lyricsSearchIndexer = nil
            lyricsSearchIndexState = .unavailable
            return
        }
        do {
            lyricsSearchIndexer = try LyricsSearchIndexer(
                package: package,
                repository: repository
            )
            lyricsSearchIndexState = .idle
        } catch {
            lyricsSearchIndexer = nil
            lyricsSearchIndexState = .failed(error.localizedDescription)
        }
    }
}

private extension LibraryStore {
    func initialSnapshot(
        from repository: LibraryRepository
    ) async throws -> InitialLibrarySnapshot {
        async let tracks = repository.tracksPage()
        async let favoriteTracks = repository.favoriteTracksPage()
        async let favoriteTrackIDs = repository.favoriteTrackIDs()
        async let recentlyPlayedTracks = repository.recentlyPlayedTracks()
        async let artists = repository.artistsPage()
        async let favoriteArtists = repository.favoriteArtistsPage()
        async let albums = repository.albumsPage()
        async let favoriteAlbums = repository.favoriteAlbumsPage()
        async let tags = repository.tagsPage()
        async let counts = repository.catalogCounts()
        async let trash = repository.trashOperations()
        return try await InitialLibrarySnapshot(
            tracks: tracks,
            favoriteTracks: favoriteTracks,
            favoriteTrackIDs: favoriteTrackIDs,
            recentlyPlayedTracks: recentlyPlayedTracks,
            artists: artists,
            favoriteArtists: favoriteArtists,
            albums: albums,
            favoriteAlbums: favoriteAlbums,
            tags: tags,
            counts: counts,
            trashOperations: trash
        )
    }

    func apply(_ snapshot: InitialLibrarySnapshot) {
        trackRequestGeneration += 1
        tracks = snapshot.tracks.items
        favoriteTracks = snapshot.favoriteTracks.items
        favoriteTrackIDs = Set(snapshot.favoriteTrackIDs)
        favoriteTrackCursor = snapshot.favoriteTracks.nextCursor
        recentlyPlayedTracks = snapshot.recentlyPlayedTracks
        trackCursor = snapshot.tracks.nextCursor
        trackQuery = .allTracks
        searchQuery = ""
        isLoadingNextTracks = false
        artists = snapshot.artists.items
        artistCursor = snapshot.artists.nextCursor
        favoriteArtists = snapshot.favoriteArtists.items
        favoriteArtistCursor = snapshot.favoriteArtists.nextCursor
        albums = snapshot.albums.items
        albumCursor = snapshot.albums.nextCursor
        favoriteAlbums = snapshot.favoriteAlbums.items
        favoriteAlbumCursor = snapshot.favoriteAlbums.nextCursor
        tags = snapshot.tags.items
        tagCursor = snapshot.tags.nextCursor
        tagGeneration &+= 1
        catalogCounts = snapshot.counts
        trashOperations = snapshot.trashOperations
        availability = .ready
    }

    func resetLibrary(availability: LibraryAvailability) {
        trackRequestGeneration += 1
        tracks = []
        favoriteTracks = []
        favoriteTrackIDs = []
        recentlyPlayedTracks = []
        playbackQueueProjectionGeneration &+= 1
        playbackQueueTracks = []
        isLoadingPlaybackQueueTracks = false
        playbackQueueProjectionError = nil
        artists = []
        favoriteArtists = []
        albums = []
        favoriteAlbums = []
        tags = []
        playlists = []
        selectedPlaylistID = nil
        selectedPlaylistTracks = []
        smartCollectionRuleData = .empty
        smartCollectionSummaries = [:]
        smartCollectionResults = [:]
        smartCollectionRuleDataGeneration &+= 1
        smartCollectionSummaryGeneration &+= 1
        smartCollectionResultGeneration &+= 1
        isLoadingNextSmartCollectionResult = false
        isLoadingSmartCollectionData = false
        trashOperations = []
        catalogCounts = .empty
        catalogSearchResults = .empty
        trackCursor = nil
        trackQuery = .allTracks
        searchQuery = ""
        isLoadingNextTracks = false
        artistCursor = nil
        albumCursor = nil
        isLoadingNextArtists = false
        isLoadingNextAlbums = false
        favoriteTrackCursor = nil
        favoriteArtistCursor = nil
        favoriteAlbumCursor = nil
        isLoadingNextFavoriteTracks = false
        isLoadingNextFavoriteArtists = false
        isLoadingNextFavoriteAlbums = false
        tagCursor = nil
        tagGeneration &+= 1
        browserArtistID = nil
        browserAlbums = []
        browserAlbumID = nil
        browserTracks = []
        browserAlbumCursor = nil
        browserTrackCursor = nil
        browserAlbumGeneration &+= 1
        browserTrackGeneration &+= 1
        isLoadingNextBrowserAlbums = false
        isLoadingNextBrowserTracks = false
        self.availability = availability
    }
}
