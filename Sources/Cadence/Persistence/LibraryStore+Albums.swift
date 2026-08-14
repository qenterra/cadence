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
}
