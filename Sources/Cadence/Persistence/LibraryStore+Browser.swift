import Foundation

extension LibraryStore {
    var canLoadMoreBrowserAlbums: Bool {
        browserAlbumCursor != nil
    }

    var canLoadMoreBrowserTracks: Bool {
        browserTrackCursor != nil
    }

    func browseAlbums(artistID: UUID?) async {
        browserAlbumGeneration += 1
        let generation = browserAlbumGeneration
        browserArtistID = artistID
        browserAlbums = []
        browserAlbumsState = artistID == nil ? .idle : .loading
        browserAlbumCursor = nil
        isLoadingNextBrowserAlbums = false

        browserTrackGeneration += 1
        browserAlbumID = nil
        browserTracks = []
        browserTracksState = .idle
        browserTrackCursor = nil
        isLoadingNextBrowserTracks = false

        guard let artistID else {
            return
        }

        do {
            let repository = try requireRepository()
            let page = try await repository.albumsPage(artistID: artistID)
            guard
                generation == browserAlbumGeneration,
                artistID == browserArtistID
            else {
                return
            }
            browserAlbums = deduplicatedAlbums(page.items)
            browserAlbumCursor = page.nextCursor
            browserAlbumsState = .ready
        } catch {
            guard generation == browserAlbumGeneration else {
                return
            }
            browserAlbumsState = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
            recordOperationFailure(.browserAlbums, error: error)
        }
    }

    func loadNextBrowserAlbums() async {
        guard
            let artistID = browserArtistID,
            let cursor = browserAlbumCursor,
            !isLoadingNextBrowserAlbums
        else {
            return
        }

        let generation = browserAlbumGeneration
        isLoadingNextBrowserAlbums = true
        do {
            let repository = try requireRepository()
            let page = try await repository.albumsPage(
                artistID: artistID,
                after: cursor
            )
            guard
                generation == browserAlbumGeneration,
                artistID == browserArtistID
            else {
                return
            }
            var existingIDs = Set(browserAlbums.map(\.id))
            browserAlbums.append(
                contentsOf: page.items.filter {
                    existingIDs.insert($0.id).inserted
                }
            )
            browserAlbumCursor = page.nextCursor
            isLoadingNextBrowserAlbums = false
        } catch {
            guard generation == browserAlbumGeneration else {
                return
            }
            isLoadingNextBrowserAlbums = false
            recordOperationFailure(.browserAlbums, error: error)
        }
    }

    func browseTracks(
        albumID: UUID?,
        sort: LibraryTrackSort? = nil
    ) async {
        browserTrackGeneration += 1
        let generation = browserTrackGeneration
        browserAlbumID = albumID
        if let sort {
            browserTrackSort = sort
        }
        browserTracks = []
        browserTracksState = albumID == nil ? .idle : .loading
        browserTrackCursor = nil
        isLoadingNextBrowserTracks = false

        guard let albumID else {
            return
        }

        let query = LibraryTrackQuery(
            scope: .album(albumID),
            sort: browserTrackSort
        )
        do {
            let repository = try requireRepository()
            let page = try await repository.tracksPage(query: query)
            guard
                generation == browserTrackGeneration,
                albumID == browserAlbumID
            else {
                return
            }
            browserTracks = deduplicatedBrowserTracks(page.items)
            browserTrackCursor = page.nextCursor
            browserTracksState = .ready
        } catch {
            guard generation == browserTrackGeneration else {
                return
            }
            browserTracksState = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
            recordOperationFailure(.browserTracks, error: error)
        }
    }

    func sortBrowserTracks(_ sort: LibraryTrackSort) async {
        guard sort != browserTrackSort else {
            return
        }
        await browseTracks(albumID: browserAlbumID, sort: sort)
    }

    func loadNextBrowserTracks() async {
        guard
            let albumID = browserAlbumID,
            let cursor = browserTrackCursor,
            !isLoadingNextBrowserTracks
        else {
            return
        }

        let generation = browserTrackGeneration
        let query = LibraryTrackQuery(
            scope: .album(albumID),
            sort: browserTrackSort
        )
        isLoadingNextBrowserTracks = true
        do {
            let repository = try requireRepository()
            let page = try await repository.tracksPage(
                query: query,
                after: cursor
            )
            guard
                generation == browserTrackGeneration,
                albumID == browserAlbumID
            else {
                return
            }
            var existingIDs = Set(browserTracks.map(\.id))
            browserTracks.append(
                contentsOf: page.items.filter {
                    existingIDs.insert($0.id).inserted
                }
            )
            browserTrackCursor = page.nextCursor
            isLoadingNextBrowserTracks = false
        } catch {
            guard generation == browserTrackGeneration else {
                return
            }
            isLoadingNextBrowserTracks = false
            recordOperationFailure(.browserTracks, error: error)
        }
    }
}

private extension LibraryStore {
    func deduplicatedAlbums(
        _ projections: [LibraryAlbumProjection]
    ) -> [LibraryAlbumProjection] {
        var seen: Set<UUID> = []
        return projections.filter { seen.insert($0.id).inserted }
    }

    func deduplicatedBrowserTracks(
        _ projections: [LibraryTrackProjection]
    ) -> [LibraryTrackProjection] {
        var seen: Set<UUID> = []
        return projections.filter { seen.insert($0.id).inserted }
    }
}
