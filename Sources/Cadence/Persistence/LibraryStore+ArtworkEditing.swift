import CoreGraphics
import Foundation

extension LibraryStore {
    func setArtwork(
        _ request: ManagedArtworkEditRequest,
        location: ManagedLibraryLocation?
    ) async throws {
        guard let artworkService, location != nil else {
            throw ManagedArtworkEditError.unavailableLibrary
        }
        let previousArtworkID = currentArtworkID(
            ownerKind: request.ownerKind,
            ownerID: request.ownerID
        )
        let newArtworkID = try await artworkService.setArtwork(request)
        previousArtworkID.map(artworkAssetCache.invalidate(id:))
        artworkAssetCache.invalidate(id: newArtworkID)
        await loadInitialLibrary()
    }

    func removeArtwork(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID,
        location: ManagedLibraryLocation?
    ) async throws {
        guard let artworkService, location != nil else {
            throw ManagedArtworkEditError.unavailableLibrary
        }
        let previousArtworkID = currentArtworkID(
            ownerKind: ownerKind,
            ownerID: ownerID
        )
        try await artworkService.removeArtwork(
            ownerKind: ownerKind,
            ownerID: ownerID
        )
        previousArtworkID.map(artworkAssetCache.invalidate(id:))
        await loadInitialLibrary()
    }

    func recoverArtworkEdits() async throws -> ManagedArtworkRecoveryResult {
        guard let artworkService else {
            return .empty
        }
        return try await artworkService.recover()
    }

    private func currentArtworkID(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID
    ) -> UUID? {
        switch ownerKind {
        case .artist:
            artists.first { $0.id == ownerID }?.customArtworkID
        case .album:
            albums.first { $0.id == ownerID }?.customArtworkID
        case .track:
            tracks.first { $0.id == ownerID }?.customArtworkID
        }
    }
}
