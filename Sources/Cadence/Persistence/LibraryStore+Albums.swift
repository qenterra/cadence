extension LibraryStore {
    func loadNextAlbums() async {
        guard
            let repository,
            let albumCursor,
            !isLoadingNextAlbums
        else {
            return
        }

        isLoadingNextAlbums = true
        defer { isLoadingNextAlbums = false }
        availability = .loading
        do {
            let page = try await repository.albumsPage(
                after: albumCursor
            )
            let existingIDs = Set(albums.map(\.id))
            albums.append(contentsOf: page.items.filter {
                !existingIDs.contains($0.id)
            })
            self.albumCursor = page.nextCursor
            availability = .ready
        } catch {
            availability = .ready
            recordOperationFailure(.albumPage, error: error)
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
            availability = .ready
            recordOperationFailure(.albumPage, error: error)
        }
    }
}
