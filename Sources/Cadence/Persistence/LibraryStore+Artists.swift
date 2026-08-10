extension LibraryStore {
    func loadNextArtists() async {
        guard
            let repository,
            let artistCursor,
            !isLoadingNextArtists
        else {
            return
        }

        isLoadingNextArtists = true
        defer { isLoadingNextArtists = false }
        availability = .loading
        do {
            let page = try await repository.artistsPage(
                after: artistCursor
            )
            let existingIDs = Set(artists.map(\.id))
            artists.append(contentsOf: page.items.filter {
                !existingIDs.contains($0.id)
            })
            self.artistCursor = page.nextCursor
            availability = .ready
        } catch {
            availability = .ready
            recordOperationFailure(.artistPage, error: error)
        }
    }

    func searchArtists(_ query: String) async {
        guard let repository else {
            artists = []
            artistCursor = nil
            availability = .empty
            return
        }

        availability = .loading
        do {
            let page = try await repository.artistsPage(search: query)
            artists = page.items
            artistCursor = page.nextCursor
            availability = .ready
        } catch {
            availability = .ready
            recordOperationFailure(.artistPage, error: error)
        }
    }
}
