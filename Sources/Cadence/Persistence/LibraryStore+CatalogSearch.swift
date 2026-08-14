import Foundation

extension LibraryStore {
    func loadNextCatalogSearchGroup(
        _ group: CatalogSearchGroup
    ) async {
        guard
            !loadingCatalogSearchGroups.contains(group),
            let cursor = catalogSearchCursor(for: group)
        else {
            return
        }
        let generation = catalogSearchGeneration
        let query = catalogSearchQuery
        loadingCatalogSearchGroups.insert(group)
        defer {
            loadingCatalogSearchGroups.remove(group)
        }
        do {
            let repository = try requireRepository()
            try await appendCatalogSearchPage(
                group,
                repository: repository,
                query: query,
                cursor: cursor,
                generation: generation
            )
        } catch {
            guard generation == catalogSearchGeneration else {
                return
            }
            recordOperationFailure(.catalogSearch, error: error)
        }
    }

    private func catalogSearchCursor(
        for group: CatalogSearchGroup
    ) -> LibraryPageCursor? {
        switch group {
        case .artists: catalogSearchResults.artistCursor
        case .albums: catalogSearchResults.albumCursor
        case .tags: catalogSearchResults.tagCursor
        case .tracks: catalogSearchResults.trackCursor
        case .lyrics: nil
        }
    }

    private func appendCatalogSearchPage(
        _ group: CatalogSearchGroup,
        repository: LibraryRepository,
        query: String,
        cursor: LibraryPageCursor,
        generation: Int
    ) async throws {
        switch group {
        case .artists:
            let page = try await repository.artistsPage(
                after: cursor,
                search: query
            )
            guard isCurrentCatalogSearch(query, generation: generation) else {
                return
            }
            catalogSearchResults.artists.append(contentsOf: page.items)
            catalogSearchResults.artistCursor = page.nextCursor
        case .albums:
            let page = try await repository.albumsPage(
                after: cursor,
                search: query
            )
            guard isCurrentCatalogSearch(query, generation: generation) else {
                return
            }
            catalogSearchResults.albums.append(contentsOf: page.items)
            catalogSearchResults.albumCursor = page.nextCursor
        case .tags:
            let page = try await repository.tagsPage(
                after: cursor,
                search: query
            )
            guard isCurrentCatalogSearch(query, generation: generation) else {
                return
            }
            catalogSearchResults.tags.append(contentsOf: page.items)
            catalogSearchResults.tagCursor = page.nextCursor
        case .tracks:
            let page = try await repository.tracksPage(
                after: cursor,
                search: query
            )
            guard isCurrentCatalogSearch(query, generation: generation) else {
                return
            }
            catalogSearchResults.tracks.append(contentsOf: page.items)
            catalogSearchResults.trackCursor = page.nextCursor
        case .lyrics:
            break
        }
    }

    private func isCurrentCatalogSearch(
        _ query: String,
        generation: Int
    ) -> Bool {
        generation == catalogSearchGeneration
            && query == catalogSearchQuery
    }
}
