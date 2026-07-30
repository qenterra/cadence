extension LibraryStore {
    func loadNextAlbums() async {
        guard let repository, let albumCursor else {
            return
        }

        availability = .loading
        do {
            let page = try await repository.albumsPage(
                after: albumCursor
            )
            albums.append(contentsOf: page.items)
            self.albumCursor = page.nextCursor
            availability = .ready
        } catch {
            availability = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
        }
    }

    func searchAlbums(_ query: String) async {
        guard let repository else {
            albums = []
            albumCursor = nil
            availability = .empty
            return
        }

        availability = .loading
        do {
            let page = try await repository.albumsPage(search: query)
            albums = page.items
            albumCursor = page.nextCursor
            availability = .ready
        } catch {
            albums = []
            albumCursor = nil
            availability = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
        }
    }
}
