import Foundation

enum CadenceOperationErrorSurface {
    case libraryOperation
    case lyricPersistence
    case artworkImport
}

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
            publishOperationError(error, on: .libraryOperation)
            return nil
        }
    }

    func setProductionTrackFavorite(
        _ track: LibraryTrackProjection,
        isFavorite: Bool
    ) async -> LibraryTrackProjection? {
        do {
            return try await librarySession.store.setTrackFavorite(
                id: track.id,
                isFavorite: isFavorite
            )
        } catch {
            publishOperationError(error, on: .libraryOperation)
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
            publishOperationError(error, on: .libraryOperation)
            return nil
        }
    }

    func publishOperationError(
        _ error: any Error,
        on surface: CadenceOperationErrorSurface
    ) {
        guard !(error is CancellationError) else {
            return
        }
        switch surface {
        case .libraryOperation:
            libraryOperationError = error.localizedDescription
        case .lyricPersistence:
            lyricPersistenceError = error.localizedDescription
        case .artworkImport:
            artworkImportError = error.localizedDescription
        }
    }
}
