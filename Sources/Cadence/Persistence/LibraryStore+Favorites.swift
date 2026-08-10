import Foundation

extension LibraryStore {
    func setTrackFavorite(
        id: UUID,
        isFavorite: Bool
    ) async throws -> LibraryTrackProjection {
        guard let repository else {
            throw LibraryFavoriteMutationError.unavailableLibrary
        }
        let projection = try await repository.setTrackFavorite(
            id: id,
            isFavorite: isFavorite
        )
        synchronizeFavoriteTrack(projection)
        return projection
    }

    func setAlbumFavorite(
        id: UUID,
        isFavorite: Bool
    ) async throws -> LibraryAlbumProjection {
        guard let repository else {
            throw LibraryFavoriteMutationError.unavailableLibrary
        }
        let projection = try await repository.setAlbumFavorite(
            id: id,
            isFavorite: isFavorite
        )
        synchronizeFavoriteAlbum(projection)
        return projection
    }

    func setArtistFavorite(
        id: UUID,
        isFavorite: Bool
    ) async throws -> LibraryArtistProjection {
        guard let repository else {
            throw LibraryFavoriteMutationError.unavailableLibrary
        }
        let projection = try await repository.setArtistFavorite(
            id: id,
            isFavorite: isFavorite
        )
        synchronizeFavoriteArtist(projection)
        return projection
    }

    func isTrackFavorite(_ id: UUID) -> Bool {
        favoriteTrackIDs.contains(id)
    }
}

private extension LibraryStore {
    func synchronizeFavoriteTrack(_ projection: LibraryTrackProjection) {
        tracks.replaceElement(id: projection.id, with: projection)
        browserTracks.replaceElement(id: projection.id, with: projection)
        selectedPlaylistTracks.replaceElement(id: projection.id, with: projection)
        recentlyPlayedTracks.replaceElement(id: projection.id, with: projection)
        playbackQueueTracks = playbackQueueTracks.map { item in
            guard item.id == projection.id else {
                return item
            }
            return PlaybackQueueTrackProjection(
                id: projection.id,
                state: .available(projection)
            )
        }
        for key in smartCollectionResults.keys {
            smartCollectionResults[key]?.tracks.replaceElement(
                id: projection.id,
                with: projection
            )
        }

        if projection.isFavorite {
            favoriteTrackIDs.insert(projection.id)
            favoriteTracks.upsert(
                projection,
                sortedBy: {
                    $0.title.localizedStandardCompare($1.title)
                        == .orderedAscending
                }
            )
        } else {
            favoriteTrackIDs.remove(projection.id)
            favoriteTracks.removeAll { $0.id == projection.id }
        }
    }

    func synchronizeFavoriteAlbum(_ projection: LibraryAlbumProjection) {
        albums.replaceElement(id: projection.id, with: projection)
        browserAlbums.replaceElement(id: projection.id, with: projection)
        if projection.isFavorite {
            favoriteAlbums.upsert(
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

    func synchronizeFavoriteArtist(_ projection: LibraryArtistProjection) {
        artists.replaceElement(id: projection.id, with: projection)
        if projection.isFavorite {
            favoriteArtists.upsert(
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
}

private extension Array where Element: Identifiable, Element.ID == UUID {
    mutating func replaceElement(id: UUID, with replacement: Element) {
        guard let index = firstIndex(where: { $0.id == id }) else {
            return
        }
        self[index] = replacement
    }

    mutating func upsert(
        _ element: Element,
        sortedBy areInIncreasingOrder: (Element, Element) -> Bool
    ) {
        if let index = firstIndex(where: { $0.id == element.id }) {
            self[index] = element
        } else {
            append(element)
        }
        sort(by: areInIncreasingOrder)
    }
}
