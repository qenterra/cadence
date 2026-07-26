import CoreGraphics
import Foundation

extension LibraryStore {
    func setArtwork(
        _ request: ManagedArtworkEditRequest,
        location: ManagedLibraryLocation?
    ) async throws {
        guard let repository, let location else {
            throw ManagedArtworkEditError.unavailableLibrary
        }
        _ = try await repository.setArtwork(
            request,
            location: location
        )
        artworkAssetCache.removeAll(keepingCapacity: true)
        await loadInitialLibrary()
    }

    func removeArtwork(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID,
        location: ManagedLibraryLocation?
    ) async throws {
        guard let repository, let location else {
            throw ManagedArtworkEditError.unavailableLibrary
        }
        try await repository.removeArtwork(
            ownerKind: ownerKind,
            ownerID: ownerID,
            location: location
        )
        artworkAssetCache.removeAll(keepingCapacity: true)
        await loadInitialLibrary()
    }
}
