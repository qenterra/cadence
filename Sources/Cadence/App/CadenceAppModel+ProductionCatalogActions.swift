import Foundation

extension CadenceAppModel {
    func renameProductionTrack(
        id: UUID,
        title: String
    ) async -> LibraryTrackProjection? {
        do {
            return try await librarySession.store.renameTrack(
                id: id,
                title: title
            )
        } catch {
            libraryOperationError = error.localizedDescription
            return nil
        }
    }

    func renameProductionAlbum(
        id: UUID,
        title: String
    ) async -> LibraryAlbumProjection? {
        do {
            return try await librarySession.store.renameAlbum(
                id: id,
                title: title
            )
        } catch {
            libraryOperationError = error.localizedDescription
            return nil
        }
    }

    func renameProductionArtist(
        id: UUID,
        name: String
    ) async -> LibraryArtistProjection? {
        do {
            return try await librarySession.store.renameArtist(
                id: id,
                name: name
            )
        } catch {
            libraryOperationError = error.localizedDescription
            return nil
        }
    }

    func playProductionAlbum(
        _ album: LibraryAlbumProjection,
        tracks: [LibraryTrackProjection],
        shuffled: Bool = false
    ) {
        guard let firstTrack = tracks.first else {
            return
        }
        playProductionTrack(
            firstTrack,
            within: tracks,
            source: .album(album.id),
            isShuffled: shuffled
        )
    }

    func playProductionArtist(
        _ artist: LibraryArtistProjection,
        tracks: [LibraryTrackProjection],
        shuffled: Bool = false
    ) {
        guard let firstTrack = tracks.first else {
            return
        }
        playProductionTrack(
            firstTrack,
            within: tracks,
            source: .artist(artist.id),
            isShuffled: shuffled
        )
    }

    func setProductionAlbumFavorite(
        _ album: LibraryAlbumProjection,
        isFavorite: Bool
    ) async -> LibraryAlbumProjection? {
        do {
            return try await librarySession.store.setAlbumFavorite(
                id: album.id,
                isFavorite: isFavorite
            )
        } catch {
            libraryOperationError = error.localizedDescription
            return nil
        }
    }

    func setProductionArtistFavorite(
        _ artist: LibraryArtistProjection,
        isFavorite: Bool
    ) async -> LibraryArtistProjection? {
        do {
            return try await librarySession.store.setArtistFavorite(
                id: artist.id,
                isFavorite: isFavorite
            )
        } catch {
            libraryOperationError = error.localizedDescription
            return nil
        }
    }
}
