import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LibraryStore {
    var mode: LibraryStoreMode
    var repository: LibraryRepository?
    @ObservationIgnored private(set) var libraryEpoch: UInt64 = 1
    @ObservationIgnored var attachmentPhase = LibraryAttachmentPhase.detached
    @ObservationIgnored var attachmentTasks:
        [UUID: LibraryAttachmentTaskEntry] = [:]
    @ObservationIgnored var initialLibraryLoadGeneration: UInt64 = 0
    var lyricsService: ManagedLyricsService?
    var artworkService: ManagedArtworkService?
    @ObservationIgnored var managedPackage: ManagedLibraryPackage?
    @ObservationIgnored var lyricsSearchIndexer: (any LyricsSearchIndexing)?
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
    @ObservationIgnored var favoriteTracksWindow: LibraryTrackWindow?
    @ObservationIgnored let tracksContentClock = TrackTableContentClock()
    @ObservationIgnored let favoriteTracksContentClock = TrackTableContentClock()
    @ObservationIgnored let browserTracksContentClock = TrackTableContentClock()
    @ObservationIgnored let selectedPlaylistTracksContentClock =
        TrackTableContentClock()
    @ObservationIgnored let catalogSearchTracksContentClock =
        TrackTableContentClock()
    private(set) var allTracksWindowContentVersion = TrackTableContentVersion(
        sourceID: UUID(),
        generation: 0
    )
    @ObservationIgnored var artworkAssetCache = ArtworkAssetCache()
    @ObservationIgnored var artworkLookupGenerations: [UUID: UInt64] = [:]
    @ObservationIgnored var artworkMetadataResults =
        ArtworkMetadataResultCache()
    @ObservationIgnored var artworkMetadataLoads:
        [UUID: ArtworkMetadataLoadEntry] = [:]
    @ObservationIgnored var artworkDataLoads:
        [ArtworkAssetCache.Key: ArtworkDataLoadEntry] = [:]
    @ObservationIgnored var artworkPublicationGeneration: UInt64 = 0
    var artworkPublication: LibraryArtworkPublication?
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
    @ObservationIgnored var selectedPlaylistTracksGeneration: UInt64 = 0
    var selectedPlaylistID: UUID? {
        didSet {
            if oldValue != selectedPlaylistID {
                selectedPlaylistTracksGeneration &+= 1
                retireSelectedPlaylistTracksContent()
                selectedPlaylistTracksState = .idle
            }
        }
    }

    private(set) var selectedPlaylistTracksOwnerID: UUID?
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
    var browserAlbumsState = LibraryContentLoadState.idle
    var browserAlbumID: UUID?
    var browserTracks: [LibraryTrackProjection] = []
    var browserTracksState = LibraryContentLoadState.idle
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
        mode = .unavailable
        repository = nil
        lyricsService = nil
        artworkService = nil
        availability = .empty
        if let container {
            let repository = LibraryRepository(modelContainer: container)
            installAttachment(repository: repository, package: package)
        }
    }
}

extension LibraryStore {
    func advanceAllTracksWindowContentVersion() {
        allTracksWindowContentVersion = allTracksWindowContentVersion.advanced()
    }

    func advanceLibraryEpoch() {
        libraryEpoch &+= 1
    }

    func searchCatalog(
        _ query: String,
        loader: LibraryCatalogSearchLoader? = nil
    ) async {
        let context = captureLibraryContext()
        catalogSearchGeneration += 1
        let generation = catalogSearchGeneration
        catalogSearchQuery = query

        guard !SearchNormalizer.normalize(query).isEmpty else {
            replaceCatalogSearchResults(with: .empty)
            isCatalogSearching = false
            return
        }

        isCatalogSearching = true
        do {
            let repository = try requireRepository()
            let loader = loader ?? { repository, query in
                try await repository.catalogSearch(query: query)
            }
            async let catalog = loader(repository, query)
            async let lyricMatches = lyricsCatalogResults(
                query: query,
                limit: 40
            )
            var results = try await catalog
            results.lyrics = await lyricMatches
            guard
                generation == catalogSearchGeneration,
                isCurrentLibraryContext(context)
            else {
                return
            }
            replaceCatalogSearchResults(with: results)
            isCatalogSearching = false
        } catch {
            guard
                generation == catalogSearchGeneration,
                isCurrentLibraryContext(context)
            else {
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
        replaceCatalogSearchResults(with: .empty)
        isCatalogSearching = false
    }

    func retireCatalogSearchForArtworkPublication() {
        catalogSearchGeneration &+= 1
        isCatalogSearching = false
        loadingCatalogSearchGroups = []
    }

    func restoreCatalogSearch(
        _ query: String,
        loader: LibraryCatalogSearchLoader? = nil
    ) {
        catalogSearchGeneration += 1
        let generation = catalogSearchGeneration
        catalogSearchQuery = query
        replaceCatalogSearchResults(with: .empty)
        isCatalogSearching = false

        guard
            mode == .production,
            !SearchNormalizer.normalize(query).isEmpty
        else {
            return
        }
        let context = captureLibraryContext()
        _ = startAttachmentTask(context: context) { [weak self] in
            guard
                let self,
                catalogSearchGeneration == generation,
                catalogSearchQuery == query
            else {
                return
            }
            await searchCatalog(query, loader: loader)
        }
    }

    func attach(
        repository: LibraryRepository,
        package: ManagedLibraryPackage? = nil,
        lyricsSearchIndexer injectedLyricsSearchIndexer:
        (any LyricsSearchIndexing)? = nil
    ) async throws {
        try await retireCurrentAttachment()
        installAttachment(
            repository: repository,
            package: package,
            lyricsSearchIndexer: injectedLyricsSearchIndexer
        )
    }

    func detach() async throws {
        try await retireCurrentAttachment()
        clearAttachment()
    }
}

private extension LibraryStore {
    func installAttachment(
        repository: LibraryRepository,
        package: ManagedLibraryPackage?,
        lyricsSearchIndexer injectedLyricsSearchIndexer:
        (any LyricsSearchIndexing)? = nil
    ) {
        resetAttachmentPublishedState(availability: .ready)
        mode = .production
        managedPackage = package
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
        favoriteTracksWindow = LibraryTrackWindow { query, offset, limit in
            try await repository.tracksWindow(
                query: query,
                offset: offset,
                limit: limit
            )
        }
        lyricsService = package.map {
            ManagedLyricsService(package: $0, repository: repository)
        }
        artworkService = package.map {
            ManagedArtworkService(package: $0, repository: repository)
        }
        if let injectedLyricsSearchIndexer {
            lyricsSearchIndexer = injectedLyricsSearchIndexer
            lyricsSearchIndexState = .idle
        } else {
            configureLyricsSearch(package: package, repository: repository)
        }
        attachmentPhase = .active
    }

    func clearAttachment() {
        resetAttachmentPublishedState(availability: .empty)
        mode = .unavailable
        repository = nil
        playlistClient = nil
        catalogLookupClient = nil
        trackPageLoader = nil
        allTracksWindow = nil
        favoriteTracksWindow = nil
        lyricsService = nil
        artworkService = nil
        managedPackage = nil
        lyricsSearchIndexer = nil
        lyricsSearchIndexState = .unavailable
        attachmentPhase = .detached
    }

    func resetAttachmentPublishedState(
        availability: LibraryAvailability
    ) {
        catalogSearchGeneration &+= 1
        catalogSearchQuery = ""
        isCatalogSearching = false
        loadingCatalogSearchGroups = []
        operationFailure = nil
        resetLibraryContent(availability: availability)
    }
}

extension LibraryStore {
    @discardableResult
    func replaceTracksContent(
        with rows: [LibraryTrackProjection]
    ) -> Bool {
        guard tracks != rows else {
            return false
        }
        tracks = rows
        tracksContentClock.advance()
        return true
    }

    @discardableResult
    func replaceFavoriteTracksContent(
        with rows: [LibraryTrackProjection]
    ) -> Bool {
        guard favoriteTracks != rows else {
            return false
        }
        favoriteTracks = rows
        favoriteTracksContentClock.advance()
        return true
    }

    @discardableResult
    func replaceBrowserTracksContent(
        with rows: [LibraryTrackProjection]
    ) -> Bool {
        guard browserTracks != rows else {
            return false
        }
        browserTracks = rows
        browserTracksContentClock.advance()
        return true
    }

    @discardableResult
    func replaceSelectedPlaylistTracksContent(
        with rows: [LibraryTrackProjection],
        ownerID: UUID?
    ) -> Bool {
        guard selectedPlaylistTracks != rows
            || selectedPlaylistTracksOwnerID != ownerID else {
            return false
        }
        selectedPlaylistTracks = rows
        selectedPlaylistTracksOwnerID = ownerID
        selectedPlaylistTracksContentClock.advance()
        return true
    }

    func retireSelectedPlaylistTracksContent() {
        replaceSelectedPlaylistTracksContent(with: [], ownerID: nil)
    }

    func replaceCatalogSearchResults(
        with results: CatalogSearchResults
    ) {
        let tracksChanged = catalogSearchResults.tracks != results.tracks
        catalogSearchResults = results
        if tracksChanged {
            catalogSearchTracksContentClock.advance()
        }
    }
}
