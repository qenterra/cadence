import Foundation

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

extension LibraryStore {
    func attach(
        repository: LibraryRepository,
        package: ManagedLibraryPackage? = nil
    ) {
        mode = .production
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
        configureLyricsSearch(package: package, repository: repository)
        availability = .ready
    }

    func detach() {
        mode = .unavailable
        repository = nil
        playlistClient = nil
        catalogLookupClient = nil
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
        guard mode == .production else {
            resetLibrary(availability: .empty)
            return
        }

        availability = .loading
        do {
            let repository = try requireRepository()
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
}

extension LibraryStore {
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
        resetCatalogContent()
        resetSmartCollections()
        resetPagination()
        resetBrowser()
        self.availability = availability
    }

    func resetCatalogContent() {
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
        playlistListState = .idle
        selectedPlaylistID = nil
        selectedPlaylistTracks = []
        selectedPlaylistTracksState = .idle
        trashOperations = []
        catalogCounts = .empty
        catalogSearchResults = .empty
    }

    func resetSmartCollections() {
        smartCollectionRuleData = .empty
        smartCollectionSummaries = [:]
        smartCollectionResults = [:]
        smartCollectionRuleDataGeneration &+= 1
        smartCollectionSummaryGeneration &+= 1
        smartCollectionResultGeneration &+= 1
        isLoadingNextSmartCollectionResult = false
        isLoadingSmartCollectionData = false
    }

    func resetPagination() {
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
    }

    func resetBrowser() {
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
    }
}
