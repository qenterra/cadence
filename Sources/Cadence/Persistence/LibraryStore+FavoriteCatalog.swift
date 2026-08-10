import Foundation

extension LibraryStore {
    var canLoadMoreFavoriteTracks: Bool {
        favoriteTrackCursor != nil
    }

    var canLoadMoreFavoriteArtists: Bool {
        favoriteArtistCursor != nil
    }

    var canLoadMoreFavoriteAlbums: Bool {
        favoriteAlbumCursor != nil
    }

    func loadFavoriteCatalog() async {
        guard let repository else {
            return
        }
        do {
            async let tracks = repository.favoriteTracksPage()
            async let trackIDs = repository.favoriteTrackIDs()
            async let albums = repository.favoriteAlbumsPage()
            async let artists = repository.favoriteArtistsPage()
            let snapshot = try await (tracks, trackIDs, albums, artists)
            favoriteTracks = snapshot.0.items
            favoriteTrackCursor = snapshot.0.nextCursor
            favoriteTrackIDs = Set(snapshot.1)
            favoriteAlbums = snapshot.2.items
            favoriteAlbumCursor = snapshot.2.nextCursor
            favoriteArtists = snapshot.3.items
            favoriteArtistCursor = snapshot.3.nextCursor
        } catch {
            recordOperationFailure(.favoriteCatalog, error: error)
        }
    }

    func loadNextFavoriteTracks() async {
        guard
            !isLoadingNextFavoriteTracks,
            let repository,
            let cursor = favoriteTrackCursor
        else {
            return
        }
        isLoadingNextFavoriteTracks = true
        defer { isLoadingNextFavoriteTracks = false }
        do {
            let page = try await repository.favoriteTracksPage(after: cursor)
            favoriteTracks.appendUnique(contentsOf: page.items)
            favoriteTrackCursor = page.nextCursor
        } catch {
            recordOperationFailure(.favoriteCatalog, error: error)
        }
    }

    func loadNextFavoriteAlbums() async {
        guard
            !isLoadingNextFavoriteAlbums,
            let repository,
            let cursor = favoriteAlbumCursor
        else {
            return
        }
        isLoadingNextFavoriteAlbums = true
        defer { isLoadingNextFavoriteAlbums = false }
        do {
            let page = try await repository.favoriteAlbumsPage(after: cursor)
            favoriteAlbums.appendUnique(contentsOf: page.items)
            favoriteAlbumCursor = page.nextCursor
        } catch {
            recordOperationFailure(.favoriteCatalog, error: error)
        }
    }

    func loadNextFavoriteArtists() async {
        guard
            !isLoadingNextFavoriteArtists,
            let repository,
            let cursor = favoriteArtistCursor
        else {
            return
        }
        isLoadingNextFavoriteArtists = true
        defer { isLoadingNextFavoriteArtists = false }
        do {
            let page = try await repository.favoriteArtistsPage(after: cursor)
            favoriteArtists.appendUnique(contentsOf: page.items)
            favoriteArtistCursor = page.nextCursor
        } catch {
            recordOperationFailure(.favoriteCatalog, error: error)
        }
    }
}

private extension Array where Element: Identifiable, Element.ID == UUID {
    mutating func appendUnique(contentsOf elements: [Element]) {
        var knownIDs = Set(map(\.id))
        append(contentsOf: elements.filter { knownIDs.insert($0.id).inserted })
    }
}
