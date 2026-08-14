import Foundation

extension LibraryStore {
    func artworkAsset(
        id: UUID,
        location: ManagedLibraryLocation?,
        variant: ArtworkAssetVariant = .thumbnail
    ) async -> ArtworkAsset? {
        guard let repository, let location else {
            return nil
        }
        guard let artwork = await artworkProjection(id: id, repository: repository) else {
            return nil
        }
        if let cached = artworkAssetCache.asset(
            id: id,
            revision: artwork.revision,
            variant: variant
        ) {
            return cached
        }
        guard let url = resolvedArtworkURL(
            relativePath: artwork.relativePath,
            location: location
        ) else {
            return nil
        }
        let key = ArtworkAssetCache.Key(
            id: id,
            revision: artwork.revision,
            variant: variant
        )
        let data = await artworkData(
            at: url,
            key: key,
            maximumPixelDimension: variant.maximumPixelDimension
        )
        guard let data, !data.isEmpty else {
            return nil
        }
        let asset = ArtworkAsset(
            id: artwork.id,
            revision: artwork.revision,
            data: data,
            variant: variant,
            scale: artwork.scale,
            normalizedOffset: CGSize(
                width: artwork.normalizedOffsetX,
                height: artwork.normalizedOffsetY
            )
        )
        artworkAssetCache.insert(asset, variant: variant)
        return asset
    }

    private func artworkProjection(
        id: UUID,
        repository: LibraryRepository
    ) async -> ManagedArtworkProjection? {
        do {
            return try await repository.artwork(id: id)
        } catch {
            return nil
        }
    }

    private func resolvedArtworkURL(
        relativePath: String,
        location: ManagedLibraryLocation
    ) -> URL? {
        do {
            return try location.resolve(relativePath: relativePath)
        } catch {
            return nil
        }
    }

    private func artworkData(
        at url: URL,
        key: ArtworkAssetCache.Key,
        maximumPixelDimension: Int?
    ) async -> Data? {
        let dataLoad: Task<Data?, Never>
        if let existing = artworkDataLoads[key] {
            dataLoad = existing
        } else {
            let created = Task.detached(priority: .utility) { () -> Data? in
                guard let source = try? Data(
                    contentsOf: url,
                    options: [.mappedIfSafe]
                ) else {
                    return nil
                }
                guard let maximumPixelDimension else {
                    return source
                }
                return ArtworkThumbnailGenerator.data(
                    from: source,
                    maximumPixelDimension: maximumPixelDimension
                ) ?? source
            }
            artworkDataLoads[key] = created
            dataLoad = created
        }
        let data = await dataLoad.value
        artworkDataLoads[key] = nil
        return data
    }
}
