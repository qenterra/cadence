import Foundation

extension LibraryStore {
    func publishFavoriteAlbumProjectionInBaseSources(
        _ projection: LibraryAlbumProjection
    ) {
        albums.replaceFavoriteElement(id: projection.id, with: projection)
        browserAlbums.replaceFavoriteElement(
            id: projection.id,
            with: projection
        )
    }

    func synchronizeFavoriteAlbumMutation(
        _ projection: LibraryAlbumProjection,
        repository: LibraryRepository,
        context: LibraryStoreContext,
        firstPageLoader: LibraryFavoriteAlbumsPageLoader
    ) async {
        guard isCurrentLibraryContext(context) else {
            return
        }
        guard favoriteAlbumCursor != nil else {
            updateCompleteFavoriteAlbumSnapshot(with: projection)
            return
        }

        updateResidentFavoriteAlbum(with: projection)
        do {
            let page = try await firstPageLoader(repository)
            guard isCurrentLibraryContext(context) else {
                return
            }
            favoriteAlbums = page.items
            favoriteAlbumCursor = page.nextCursor
        } catch {
            guard isCurrentLibraryContext(context) else {
                return
            }
            recordOperationFailure(.favoriteCatalog, error: error)
        }
    }

    func publishFavoriteArtistProjectionInBaseSources(
        _ projection: LibraryArtistProjection
    ) {
        artists.replaceFavoriteElement(id: projection.id, with: projection)
    }

    func synchronizeFavoriteArtistMutation(
        _ projection: LibraryArtistProjection,
        repository: LibraryRepository,
        context: LibraryStoreContext,
        firstPageLoader: LibraryFavoriteArtistsPageLoader
    ) async {
        guard isCurrentLibraryContext(context) else {
            return
        }
        guard favoriteArtistCursor != nil else {
            updateCompleteFavoriteArtistSnapshot(with: projection)
            return
        }

        updateResidentFavoriteArtist(with: projection)
        do {
            let page = try await firstPageLoader(repository)
            guard isCurrentLibraryContext(context) else {
                return
            }
            favoriteArtists = page.items
            favoriteArtistCursor = page.nextCursor
        } catch {
            guard isCurrentLibraryContext(context) else {
                return
            }
            recordOperationFailure(.favoriteCatalog, error: error)
        }
    }
}

private extension LibraryStore {
    func updateCompleteFavoriteAlbumSnapshot(
        with projection: LibraryAlbumProjection
    ) {
        if projection.isFavorite {
            favoriteAlbums.upsertFavoriteElement(
                projection,
                sortedBy: {
                    $0.title.localizedStandardCompare($1.title)
                        == .orderedAscending
                }
            )
        } else {
            favoriteAlbums.removeAll { $0.id == projection.id }
        }
    }

    func updateResidentFavoriteAlbum(
        with projection: LibraryAlbumProjection
    ) {
        if projection.isFavorite {
            favoriteAlbums.replaceFavoriteElement(
                id: projection.id,
                with: projection
            )
        } else {
            favoriteAlbums.removeAll { $0.id == projection.id }
        }
    }

    func updateCompleteFavoriteArtistSnapshot(
        with projection: LibraryArtistProjection
    ) {
        if projection.isFavorite {
            favoriteArtists.upsertFavoriteElement(
                projection,
                sortedBy: {
                    $0.name.localizedStandardCompare($1.name)
                        == .orderedAscending
                }
            )
        } else {
            favoriteArtists.removeAll { $0.id == projection.id }
        }
    }

    func updateResidentFavoriteArtist(
        with projection: LibraryArtistProjection
    ) {
        if projection.isFavorite {
            favoriteArtists.replaceFavoriteElement(
                id: projection.id,
                with: projection
            )
        } else {
            favoriteArtists.removeAll { $0.id == projection.id }
        }
    }
}

private extension Array where Element: Identifiable & Equatable, Element.ID == UUID {
    @discardableResult
    mutating func replaceFavoriteElement(
        id: UUID,
        with replacement: Element
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard self[index] != replacement else {
            return false
        }
        self[index] = replacement
        return true
    }

    @discardableResult
    mutating func upsertFavoriteElement(
        _ element: Element,
        sortedBy areInIncreasingOrder: (Element, Element) -> Bool
    ) -> Bool {
        let before = self
        if let index = firstIndex(where: { $0.id == element.id }) {
            self[index] = element
        } else {
            append(element)
        }
        sort(by: areInIncreasingOrder)
        return self != before
    }
}
