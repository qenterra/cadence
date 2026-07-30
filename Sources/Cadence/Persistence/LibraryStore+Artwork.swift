import Foundation

extension LibraryStore {
    func artworkAsset(
        id: UUID,
        location: ManagedLibraryLocation?
    ) async -> ArtworkAsset? {
        guard let repository, let location else {
            return nil
        }
        let projection: ManagedArtworkProjection?
        do {
            projection = try await repository.artwork(id: id)
        } catch {
            return nil
        }
        guard let artwork = projection else {
            return nil
        }
        if let cached = artworkAssetCache[id],
           cached.revision == artwork.revision {
            return cached
        }
        let url: URL
        do {
            url = try location.resolve(relativePath: artwork.relativePath)
        } catch {
            return nil
        }
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
        guard let data, !data.isEmpty else {
            return nil
        }
        let asset = ArtworkAsset(
            id: artwork.id,
            revision: artwork.revision,
            data: data,
            scale: artwork.scale,
            normalizedOffset: CGSize(
                width: artwork.normalizedOffsetX,
                height: artwork.normalizedOffsetY
            )
        )
        artworkAssetCache[id] = asset
        return asset
    }
}
