import Foundation

extension LibraryStore {
    func resetLibrary(availability: LibraryAvailability) {
        artworkPublication = nil
        resetCatalogContent()
        resetSmartCollections()
        resetPagination()
        resetBrowser()
        self.availability = availability
    }
}

private extension LibraryStore {
    func resetCatalogContent() {
        trackRequestGeneration += 1
        replaceTracksContent(with: [])
        replaceFavoriteTracksContent(with: [])
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
        selectedPlaylistTracksGeneration &+= 1
        selectedPlaylistID = nil
        replaceSelectedPlaylistTracksContent(with: [], ownerID: nil)
        selectedPlaylistTracksState = .idle
        trashOperations = []
        catalogCounts = .empty
        replaceCatalogSearchResults(with: .empty)
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
        browserAlbumsState = .idle
        browserAlbumID = nil
        replaceBrowserTracksContent(with: [])
        browserTracksState = .idle
        browserAlbumCursor = nil
        browserTrackCursor = nil
        browserAlbumGeneration &+= 1
        browserTrackGeneration &+= 1
        isLoadingNextBrowserAlbums = false
        isLoadingNextBrowserTracks = false
    }
}
