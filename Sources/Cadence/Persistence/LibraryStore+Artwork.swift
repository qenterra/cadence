import Foundation

extension LibraryStore {
    func artworkAsset(
        id: UUID,
        location: ManagedLibraryLocation?,
        variant: ArtworkAssetVariant = .thumbnail
    ) async -> ArtworkAsset? {
        guard let location else {
            return nil
        }
        do {
            let repository = try requireRepository()
            guard let artwork = try await repository.artwork(id: id) else {
                return nil
            }
            if let cached = artworkAssetCache.asset(
                id: id,
                revision: artwork.revision,
                variant: variant
            ) {
                return cached
            }
            let url = try location.resolve(relativePath: artwork.relativePath)
            let key = ArtworkAssetCache.Key(
                id: id,
                revision: artwork.revision,
                variant: variant
            )
            let data = try await artworkData(
                at: url,
                key: key,
                maximumPixelDimension: variant.maximumPixelDimension
            )
            guard !data.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
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
        } catch {
            recordOperationFailure(.artworkLoad, error: error)
            return nil
        }
    }

    private func artworkData(
        at url: URL,
        key: ArtworkAssetCache.Key,
        maximumPixelDimension: Int?
    ) async throws -> Data {
        let dataLoad: Task<Data, Error>
        if let existing = artworkDataLoads[key] {
            dataLoad = existing
        } else {
            let created = Task.detached(priority: .utility) { () throws -> Data in
                let source = try Data(
                    contentsOf: url,
                    options: [.mappedIfSafe]
                )
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
        defer { artworkDataLoads[key] = nil }
        return try await dataLoad.value
    }
}
