extension LibraryStore {
    func loadNextArtists() async {
        guard let repository, let artistCursor else {
            return
        }

        availability = .loading
        do {
            let page = try await repository.artistsPage(
                after: artistCursor
            )
            artists.append(contentsOf: page.items)
            self.artistCursor = page.nextCursor
            availability = .ready
        } catch {
            availability = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
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
            artists = []
            artistCursor = nil
            availability = .failed(
                LibraryStoreFailure(message: error.localizedDescription)
            )
        }
    }
}
