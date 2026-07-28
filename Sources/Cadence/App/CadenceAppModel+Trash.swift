import Foundation

extension CadenceAppModel {
    func requestLibraryDeletion(
        kind: TrashTargetKind,
        id: UUID,
        title: String
    ) {
        pendingLibraryDeletion = PendingLibraryDeletion(
            kind: kind,
            id: id,
            title: title
        )
    }

    func cancelLibraryDeletion() {
        pendingLibraryDeletion = nil
    }

    func confirmLibraryDeletion() async {
        guard let pending = pendingLibraryDeletion else {
            return
        }
        pendingLibraryDeletion = nil
        let affectedTrackIDs = productionTrackIDs(for: pending)
        let shouldStopPlayback = switch pending.kind {
        case .track:
            currentPlaybackTrack?.id == pending.id
        case .album:
            currentPlaybackTrack?.albumID == pending.id
        case .artist:
            currentPlaybackTrack?.artistID == pending.id
        }
        if shouldStopPlayback {
            playbackCoordinator?.stop()
        } else {
            _ = playbackCoordinator?.removeUpNext(affectedTrackIDs)
        }
        do {
            try await librarySession.store.moveToTrash(
                targetKind: pending.kind,
                targetID: pending.id,
                location: librarySession.location
            )
            repairProductionNavigationAfterDeletion()
        } catch {
            libraryOperationError = error.localizedDescription
        }
    }

    func emptyProductionTrash() async {
        do {
            try await librarySession.store.emptyTrash(
                location: librarySession.location
            )
        } catch {
            libraryOperationError = error.localizedDescription
        }
    }

    func restoreProductionTrash(operationID: UUID) async {
        do {
            try await librarySession.store.restoreTrash(
                operationID: operationID,
                location: librarySession.location
            )
        } catch {
            libraryOperationError = error.localizedDescription
        }
    }

    func permanentlyDeleteProductionTrash(operationID: UUID) async {
        do {
            try await librarySession.store.emptyTrash(
                operationIDs: [operationID],
                location: librarySession.location
            )
        } catch {
            libraryOperationError = error.localizedDescription
        }
    }

    func dismissLibraryOperationError() {
        libraryOperationError = nil
    }

    private func repairProductionNavigationAfterDeletion() {
        let store = librarySession.store
        if let id = selectedProductionArtistID,
           !store.artists.contains(where: { $0.id == id }) {
            selectedProductionArtistID = nil
        }
        if let id = selectedProductionAlbumID,
           !store.albums.contains(where: { $0.id == id }) {
            selectedProductionAlbumID = nil
        }
        if let id = selectedProductionTagEditingTrackID,
           !store.tracks.contains(where: { $0.id == id }) {
            selectedProductionTagEditingTrackID = nil
        }
    }

    private func productionTrackIDs(
        for deletion: PendingLibraryDeletion
    ) -> [UUID] {
        librarySession.store.tracks.compactMap { track in
            let isAffected = switch deletion.kind {
            case .track:
                track.id == deletion.id
            case .album:
                track.albumID == deletion.id
            case .artist:
                track.artistID == deletion.id
            }
            return isAffected ? track.id : nil
        }
    }
}
