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
        if let cached = artworkAssetCache.asset(
            id: id,
            revision: artwork.revision
        ) {
            return cached
        }
        let url: URL
        do {
            url = try location.resolve(relativePath: artwork.relativePath)
        } catch {
            return nil
        }
        let key = ArtworkAssetCache.Key(
            id: id,
            revision: artwork.revision
        )
        let data = await artworkData(at: url, key: key)
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
        artworkAssetCache.insert(asset)
        return asset
    }

    private func artworkData(
        at url: URL,
        key: ArtworkAssetCache.Key
    ) async -> Data? {
        let dataLoad: Task<Data?, Never>
        if let existing = artworkDataLoads[key] {
            dataLoad = existing
        } else {
            let created = Task.detached(priority: .utility) {
                try? Data(contentsOf: url, options: [.mappedIfSafe])
            }
            artworkDataLoads[key] = created
            dataLoad = created
        }
        let data = await dataLoad.value
        artworkDataLoads[key] = nil
        return data
    }
}
