extension LibraryStore {
    convenience init(trackPageLoader: @escaping LibraryTrackPageLoader) {
        self.init()
        mode = .trackPageFixture
        attachmentPhase = .active
        self.trackPageLoader = trackPageLoader
        availability = .ready
    }

    convenience init(playlistClient: LibraryPlaylistClient) {
        self.init()
        mode = .playlistFixture
        attachmentPhase = .active
        self.playlistClient = playlistClient
        availability = .ready
    }

    convenience init(catalogLookupClient: LibraryCatalogLookupClient) {
        self.init()
        mode = .catalogLookupFixture
        attachmentPhase = .active
        self.catalogLookupClient = catalogLookupClient
        availability = .ready
    }
}
