import AppKit
import MediaPlayer

@MainActor
protocol SystemMediaArtworkProviding: AnyObject {
    func artwork(for id: UUID) async -> MPMediaItemArtwork?
}

private struct SendableSystemMediaImage: @unchecked Sendable {
    let value: NSImage
}

private func makeSystemMediaArtwork(
    image: SendableSystemMediaImage
) -> MPMediaItemArtwork {
    MPMediaItemArtwork(
        boundsSize: image.value.size
    ) { _ in
        image.value
    }
}

@MainActor
final class SystemMediaArtworkProvider: SystemMediaArtworkProviding {
    typealias AssetLoader = @MainActor (UUID) async -> ArtworkAsset?

    private struct CacheKey: Hashable {
        let id: UUID
        let revision: Int
    }

    private let loadAsset: AssetLoader
    private var cache: [CacheKey: MPMediaItemArtwork] = [:]

    init(loadAsset: @escaping AssetLoader) {
        self.loadAsset = loadAsset
    }

    func artwork(for id: UUID) async -> MPMediaItemArtwork? {
        guard let asset = await loadAsset(id) else {
            return nil
        }
        let key = CacheKey(id: id, revision: asset.revision)
        if let cached = cache[key] {
            return cached
        }

        let data = asset.data
        guard let image = await Task.detached(priority: .utility, operation: {
            NSImage(data: data).map(SendableSystemMediaImage.init)
        }).value?.value else {
            return nil
        }
        let artwork = makeSystemMediaArtwork(
            image: SendableSystemMediaImage(value: image)
        )
        cache = cache.filter { $0.key.id != id }
        cache[key] = artwork
        return artwork
    }
}
