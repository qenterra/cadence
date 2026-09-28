import Foundation

enum CadenceOperationErrorSurface {
    case libraryOperation
    case lyricPersistence
    case artworkImport
}

extension CadenceAppModel {
    func presentTrackMetadataEditor(_ track: LibraryTrackProjection) {
        guard runtimeMode == .production else {
            return
        }
        pendingTrackMetadataEdit = TrackMetadataEditPresentation(track: track)
    }

    func presentTrackMetadataEditor(_ track: PlaybackTrack) {
        guard runtimeMode == .production, !isCurrentPlaybackExternal else {
            return
        }
        pendingTrackMetadataEdit = TrackMetadataEditPresentation(track: track)
    }

    func dismissTrackMetadataEditor() {
        pendingTrackMetadataEdit = nil
    }

    @discardableResult
    func saveTrackMetadata(
        _ edit: ManagedAudioMetadataEdit,
        for presentation: TrackMetadataEditPresentation
    ) async -> Bool {
        guard
            pendingTrackMetadataEdit?.id == presentation.id,
            let location = librarySession.location
        else {
            return false
        }
        do {
            let updated = try await librarySession.store.editManagedTrackMetadata(
                trackID: presentation.id,
                relativeMediaPath: presentation.relativeMediaPath,
                edit: edit,
                location: location
            )
            await playbackCoordinator?.refreshManagedTrackMetadata(
                trackID: updated.id
            )
            if pendingTrackMetadataEdit?.id == presentation.id {
                pendingTrackMetadataEdit = nil
            }
            return true
        } catch {
            libraryOperationError = error.localizedDescription
            return false
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

    func updateProductionArtist(
        id: UUID,
        name: String,
        userDescription: String?
    ) async -> LibraryArtistProjection? {
        do {
            return try await librarySession.store.updateArtist(
                id: id,
                name: name,
                userDescription: userDescription
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
