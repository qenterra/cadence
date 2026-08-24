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

    func requestLibraryDeletion(
        trackIDs: [UUID],
        title: String
    ) {
        let orderedIDs = Array(NSOrderedSet(array: trackIDs))
            .compactMap { $0 as? UUID }
        guard !orderedIDs.isEmpty else {
            return
        }
        pendingLibraryDeletion = PendingLibraryDeletion(
            kind: .track,
            ids: orderedIDs,
            title: title
        )
    }

    func cancelLibraryDeletion() {
        pendingLibraryDeletion = nil
    }

    func confirmLibraryDeletion(
        _ pending: PendingLibraryDeletion
    ) async {
        pendingLibraryDeletion = nil
        let affectedTrackIDs = productionTrackIDs(for: pending)
        let pendingIDs = Set(pending.ids)
        let shouldStopPlayback = switch pending.kind {
        case .track:
            currentPlaybackTrack.map { pendingIDs.contains($0.id) } == true
        case .album:
            currentPlaybackTrack?.albumID.map(pendingIDs.contains) == true
        case .artist:
            currentPlaybackTrack?.artistID.map(pendingIDs.contains) == true
        }
        if shouldStopPlayback {
            playbackCoordinator?.stop()
        } else {
            _ = playbackCoordinator?.removeUpNext(affectedTrackIDs)
        }
        do {
            if pending.kind == .track {
                try await librarySession.store.moveToTrash(
                    trackIDs: pending.ids,
                    location: librarySession.location
                )
            } else if let targetID = pending.id {
                try await librarySession.store.moveToTrash(
                    targetKind: pending.kind,
                    targetID: targetID,
                    location: librarySession.location
                )
            }
            repairProductionNavigationAfterDeletion()
        } catch {
            publishOperationError(error, on: .libraryOperation)
        }
    }

    func emptyProductionTrash() async {
        do {
            try await librarySession.store.emptyTrash(
                location: librarySession.location
            )
        } catch {
            publishOperationError(error, on: .libraryOperation)
        }
    }

    func restoreProductionTrash(operationID: UUID) async {
        do {
            try await librarySession.store.restoreTrash(
                operationID: operationID,
                location: librarySession.location
            )
        } catch {
            publishOperationError(error, on: .libraryOperation)
        }
    }

    func permanentlyDeleteProductionTrash(operationID: UUID) async {
        do {
            try await librarySession.store.emptyTrash(
                operationIDs: [operationID],
                location: librarySession.location
            )
        } catch {
            publishOperationError(error, on: .libraryOperation)
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
        let targetIDs = Set(deletion.ids)
        return librarySession.store.tracks.compactMap { track in
            let isAffected = switch deletion.kind {
            case .track:
                targetIDs.contains(track.id)
            case .album:
                track.albumID.map(targetIDs.contains) == true
            case .artist:
                track.artistID.map(targetIDs.contains) == true
            }
            return isAffected ? track.id : nil
        }
    }
}
