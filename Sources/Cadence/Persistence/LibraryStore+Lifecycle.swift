import Foundation

struct InitialLibrarySnapshot: Sendable {
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

typealias InitialLibrarySnapshotLoader = @Sendable (
    _ repository: LibraryRepository
) async throws -> InitialLibrarySnapshot

private struct SemanticTrackSourceRefresh: Sendable {
    let browserAlbumID: UUID?
    let browserSort: LibraryTrackSort
    let browserGeneration: Int
    let playlistID: UUID?
    let playlistGeneration: UInt64
    let catalogSearchQuery: String?
    let catalogSearchGeneration: Int
    let playbackQueueIDs: [UUID]
    let playbackQueueGeneration: Int
    let smartResultRule: SmartCollectionRuleGroup?
    let smartResultGeneration: Int
    let smartSummaryRules: [SmartCollectionRuleGroup]
    let smartSummaryGeneration: Int
}

typealias LibraryTrackPageLoader = @Sendable (
    _ query: LibraryTrackQuery,
    _ cursor: LibraryPageCursor?
) async throws -> LibraryPage<LibraryTrackProjection>

extension LibraryStore {
    func loadInitialLibrary(
        snapshotLoader: InitialLibrarySnapshotLoader? = nil
    ) async {
        initialLibraryLoadGeneration &+= 1
        let generation = initialLibraryLoadGeneration
        let context = captureLibraryContext()
        guard mode == .production else {
            resetLibrary(availability: .empty)
            return
        }

        availability = .loading
        do {
            let repository = try requireRepository()
            let snapshot = if let snapshotLoader {
                try await snapshotLoader(repository)
            } else {
                try await initialSnapshot(from: repository)
            }
            guard
                generation == initialLibraryLoadGeneration,
                isCurrentLibraryContext(context)
            else {
                return
            }
            apply(snapshot)
            await synchronizeLyricsSearch(for: context)
        } catch {
            guard
                generation == initialLibraryLoadGeneration,
                isCurrentLibraryContext(context)
            else {
                return
            }
            resetLibrary(
                availability: .failed(
                    LibraryStoreFailure(message: error.localizedDescription)
                )
            )
        }
    }

    func refreshAfterMetadataRepair(
        repairedCount: Int,
        context: LibraryStoreContext? = nil
    ) async {
        let context = context ?? captureLibraryContext()
        guard
            repairedCount > 0,
            isCurrentLibraryContext(context)
        else {
            return
        }
        await refreshAfterSemanticTrackMutation(context: context)
    }

    func refreshAfterSemanticTrackMutation(
        context: LibraryStoreContext? = nil
    ) async {
        let context = context ?? captureLibraryContext()
        guard isCurrentLibraryContext(context) else {
            return
        }
        let refresh = retireActiveTrackSourcesForSemanticRefresh()
        advanceAllTracksWindowContentVersion()
        await loadInitialLibrary()
        guard
            isCurrentLibraryContext(context),
            availability == .ready
        else {
            return
        }
        await reloadActiveTrackSources(after: refresh, context: context)
    }

    func resetLibraryContent(
        availability: LibraryAvailability
    ) {
        resetLibrary(availability: availability)
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
    func retireActiveTrackSourcesForSemanticRefresh()
        -> SemanticTrackSourceRefresh {
        let browserAlbumID = browserAlbumID
        let browserSort = browserTrackSort
        let playlistID = selectedPlaylistID
        let searchQuery = activeCatalogSearchQuery
        let playbackQueueIDs = playbackQueueTracks.map(\.id)
        let smartResultRule = smartCollectionResults.keys.first
        let smartSummaryRules = Array(
            Set(smartCollectionSummaries.keys).subtracting(
                smartResultRule.map { [$0] } ?? []
            )
        )
        retireBrowserSource(hasActiveAlbum: browserAlbumID != nil)
        retirePlaylistSource(hasSelection: playlistID != nil)
        retireCatalogSearchSource(hasQuery: searchQuery != nil)
        retirePlaybackQueueSource(ids: playbackQueueIDs)
        retireSmartCollectionSources()

        return SemanticTrackSourceRefresh(
            browserAlbumID: browserAlbumID,
            browserSort: browserSort,
            browserGeneration: browserTrackGeneration,
            playlistID: playlistID,
            playlistGeneration: selectedPlaylistTracksGeneration,
            catalogSearchQuery: searchQuery,
            catalogSearchGeneration: catalogSearchGeneration,
            playbackQueueIDs: playbackQueueIDs,
            playbackQueueGeneration: playbackQueueProjectionGeneration,
            smartResultRule: smartResultRule,
            smartResultGeneration: smartCollectionResultGeneration,
            smartSummaryRules: smartSummaryRules,
            smartSummaryGeneration: smartCollectionSummaryGeneration
        )
    }

    var activeCatalogSearchQuery: String? {
        guard !SearchNormalizer.normalize(catalogSearchQuery).isEmpty else {
            return nil
        }
        return catalogSearchQuery
    }

    func retireBrowserSource(hasActiveAlbum: Bool) {
        browserTrackGeneration &+= 1
        browserTrackCursor = nil
        isLoadingNextBrowserTracks = false
        guard hasActiveAlbum else {
            return
        }
        replaceBrowserTracksContent(with: [])
        browserTracksState = .loading
    }

    func retirePlaylistSource(hasSelection: Bool) {
        selectedPlaylistTracksGeneration &+= 1
        guard hasSelection else {
            return
        }
        retireSelectedPlaylistTracksContent()
        selectedPlaylistTracksState = .loading
    }

    func retireCatalogSearchSource(hasQuery: Bool) {
        catalogSearchGeneration &+= 1
        loadingCatalogSearchGroups = []
        guard hasQuery else {
            return
        }
        replaceCatalogSearchResults(with: .empty)
    }

    func retirePlaybackQueueSource(ids: [UUID]) {
        playbackQueueProjectionGeneration &+= 1
        guard !ids.isEmpty else {
            return
        }
        playbackQueueTracks = ids.map {
            PlaybackQueueTrackProjection(id: $0, state: .loading)
        }
        playbackQueueProjectionError = nil
        isLoadingPlaybackQueueTracks = true
    }

    func retireSmartCollectionSources() {
        smartCollectionSummaryGeneration &+= 1
        smartCollectionResultGeneration &+= 1
        smartCollectionSummaries = [:]
        smartCollectionResults = [:]
        isLoadingNextSmartCollectionResult = false
    }

    func reloadActiveTrackSources(
        after refresh: SemanticTrackSourceRefresh,
        context: LibraryStoreContext
    ) async {
        guard
            isCurrentLibraryContext(context),
            await reloadBrowserSource(after: refresh, context: context),
            await reloadPlaylistSource(after: refresh, context: context),
            await reloadCatalogSearchSource(after: refresh, context: context),
            await reloadPlaybackQueueSource(after: refresh, context: context),
            await reloadSmartSummaries(after: refresh, context: context)
        else {
            return
        }
        await reloadSmartResult(after: refresh)
    }

    func reloadBrowserSource(
        after refresh: SemanticTrackSourceRefresh,
        context: LibraryStoreContext
    ) async -> Bool {
        guard
            let albumID = refresh.browserAlbumID,
            refresh.browserGeneration == browserTrackGeneration,
            albumID == browserAlbumID,
            refresh.browserSort == browserTrackSort
        else {
            return true
        }
        await browseTracks(albumID: albumID, sort: refresh.browserSort)
        return isCurrentLibraryContext(context)
    }

    func reloadPlaylistSource(
        after refresh: SemanticTrackSourceRefresh,
        context: LibraryStoreContext
    ) async -> Bool {
        guard
            let playlistID = refresh.playlistID,
            refresh.playlistGeneration == selectedPlaylistTracksGeneration,
            playlistID == selectedPlaylistID
        else {
            return true
        }
        await loadSelectedPlaylistTracks()
        return isCurrentLibraryContext(context)
    }

    func reloadCatalogSearchSource(
        after refresh: SemanticTrackSourceRefresh,
        context: LibraryStoreContext
    ) async -> Bool {
        guard
            let query = refresh.catalogSearchQuery,
            refresh.catalogSearchGeneration == catalogSearchGeneration,
            query == catalogSearchQuery
        else {
            return true
        }
        await searchCatalog(query)
        return isCurrentLibraryContext(context)
    }

    func reloadPlaybackQueueSource(
        after refresh: SemanticTrackSourceRefresh,
        context: LibraryStoreContext
    ) async -> Bool {
        guard
            !refresh.playbackQueueIDs.isEmpty,
            refresh.playbackQueueGeneration
            == playbackQueueProjectionGeneration
        else {
            return true
        }
        await loadPlaybackQueueTracks(ids: refresh.playbackQueueIDs)
        return isCurrentLibraryContext(context)
    }

    func reloadSmartSummaries(
        after refresh: SemanticTrackSourceRefresh,
        context: LibraryStoreContext
    ) async -> Bool {
        guard
            refresh.smartSummaryGeneration == smartCollectionSummaryGeneration
        else {
            return true
        }
        await loadSmartCollectionSummaries(rules: refresh.smartSummaryRules)
        return isCurrentLibraryContext(context)
    }

    func reloadSmartResult(after refresh: SemanticTrackSourceRefresh) async {
        guard
            let rule = refresh.smartResultRule,
            refresh.smartResultGeneration == smartCollectionResultGeneration
        else {
            return
        }
        await loadSmartCollectionResult(rule: rule)
    }

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
        async let trash = repository.trashOperations(
            location: managedPackage?.location
        )
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
        replaceTracksContent(with: snapshot.tracks.items)
        replaceFavoriteTracksContent(with: snapshot.favoriteTracks.items)
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
}
