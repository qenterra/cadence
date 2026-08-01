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

@MainActor
@Observable
final class LibraryStore {
    private(set) var repository: LibraryRepository?
    private(set) var lyricsService: ManagedLyricsService?
    private(set) var artworkService: ManagedArtworkService?
    var trackCursor: LibraryPageCursor?
    var trackRequestGeneration = 0
    var tagCursor: LibraryPageCursor?
    var tagGeneration = 0
    var isLoadingNextTags = false
    private var catalogSearchGeneration = 0
    private var playbackQueueProjectionGeneration = 0
    @ObservationIgnored var trackPageLoader: LibraryTrackPageLoader?
    @ObservationIgnored let artworkAssetCache = ArtworkAssetCache()
    @ObservationIgnored var artworkDataLoads: [ArtworkAssetCache.Key: Task<Data?, Never>] = [:]
    var artistCursor: LibraryPageCursor?
    var albumCursor: LibraryPageCursor?

    var availability: LibraryAvailability
    var tracks: [LibraryTrackProjection] = []
    private(set) var playbackQueueTracks: [PlaybackQueueTrackProjection] = []
    private(set) var isLoadingPlaybackQueueTracks = false
    private(set) var playbackQueueProjectionError: LibraryStoreFailure?
    var artists: [LibraryArtistProjection] = []
    var albums: [LibraryAlbumProjection] = []
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
            artworkService = package.map {
                ManagedArtworkService(
                    package: $0,
                    repository: repository
                )
            }
            availability = .ready
        } else {
            repository = nil
            trackPageLoader = nil
            lyricsService = nil
            artworkService = nil
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

    func loadNextTags() async {
        guard
            !isLoadingNextTags,
            let repository,
            let tagCursor
        else {
            return
        }

        isLoadingNextTags = true
        let generation = tagGeneration
        defer {
            isLoadingNextTags = false
        }

        do {
            let page = try await repository.tagsPage(after: tagCursor)
            guard generation == tagGeneration else {
                return
            }
            let existingIDs = Set(tags.map(\.id))
            tags.append(
                contentsOf: page.items.filter {
                    !existingIDs.contains($0.id)
                }
            )
            self.tagCursor = page.nextCursor
        } catch {
            guard generation == tagGeneration else {
                return
            }
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
        tagCursor = snapshot.tags.nextCursor
        tagGeneration &+= 1
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
        tagCursor = nil
        tagGeneration &+= 1
        self.availability = availability
    }
}
