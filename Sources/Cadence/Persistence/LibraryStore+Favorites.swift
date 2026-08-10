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
        tracks.replaceElement(id: id, with: projection)
        browserTracks.replaceElement(id: id, with: projection)
        selectedPlaylistTracks.replaceElement(id: id, with: projection)
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
        albums.replaceElement(id: id, with: projection)
        browserAlbums.replaceElement(id: id, with: projection)
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
        artists.replaceElement(id: id, with: projection)
        return projection
    }
}

private extension Array where Element: Identifiable, Element.ID == UUID {
    mutating func replaceElement(id: UUID, with replacement: Element) {
        guard let index = firstIndex(where: { $0.id == id }) else {
            return
        }
        self[index] = replacement
    }
}
