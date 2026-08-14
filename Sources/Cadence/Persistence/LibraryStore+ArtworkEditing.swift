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
        let previousArtworkID = try await currentArtworkID(
            ownerKind: request.ownerKind,
            ownerID: request.ownerID
        )
        let newArtworkID = try await artworkService.setArtwork(request)
        previousArtworkID.map { artworkAssetCache.invalidate(id: $0) }
        artworkAssetCache.invalidate(id: newArtworkID)
        await loadInitialLibrary()
        if request.ownerKind == .playlist {
            await loadPlaylists()
        }
    }

    func removeArtwork(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID,
        location: ManagedLibraryLocation?
    ) async throws {
        guard let artworkService, location != nil else {
            throw ManagedArtworkEditError.unavailableLibrary
        }
        let previousArtworkID = try await currentArtworkID(
            ownerKind: ownerKind,
            ownerID: ownerID
        )
        try await artworkService.removeArtwork(
            ownerKind: ownerKind,
            ownerID: ownerID
        )
        previousArtworkID.map { artworkAssetCache.invalidate(id: $0) }
        await loadInitialLibrary()
        if ownerKind == .playlist {
            await loadPlaylists()
        }
    }

    func recoverArtworkEdits() async throws -> ManagedArtworkRecoveryResult {
        guard let artworkService else {
            throw ManagedArtworkEditError.unavailableLibrary
        }
        return try await artworkService.recover()
    }

    private func currentArtworkID(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID
    ) async throws -> UUID? {
        let cachedID: UUID? = switch ownerKind {
        case .artist:
            artists.first { $0.id == ownerID }?.customArtworkID
        case .album:
            albums.first { $0.id == ownerID }?.customArtworkID
        case .track:
            tracks.first { $0.id == ownerID }?.customArtworkID
        case .playlist:
            playlists.first { $0.id == ownerID }?.customArtworkID
        case .smartCollection:
            nil
        }
        if let cachedID {
            return cachedID
        }
        let repository = try requireRepository()
        return try await repository.artworkEditSnapshot(
            ownerKind: ownerKind,
            ownerID: ownerID
        )?.id
    }
}
