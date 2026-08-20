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
    ) { requestedSize in
        resizedSystemMediaImage(
            image.value,
            requestedSize: requestedSize
        )
    }
}

private func resizedSystemMediaImage(
    _ image: NSImage,
    requestedSize: NSSize
) -> NSImage {
    guard
        requestedSize.width > 0,
        requestedSize.height > 0,
        image.size != requestedSize
    else {
        return image
    }
    var sourceRect = NSRect(origin: .zero, size: image.size)
    guard let source = image.cgImage(
        forProposedRect: &sourceRect,
        context: nil,
        hints: nil
    ) else {
        let copy = image.copy() as? NSImage ?? image
        copy.size = requestedSize
        return copy
    }
    let pixelWidth = max(Int(requestedSize.width.rounded(.up)), 1)
    let pixelHeight = max(Int(requestedSize.height.rounded(.up)), 1)
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        let copy = image.copy() as? NSImage ?? image
        copy.size = requestedSize
        return copy
    }
    context.interpolationQuality = .high
    context.draw(
        source,
        in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    )
    guard let output = context.makeImage() else {
        let copy = image.copy() as? NSImage ?? image
        copy.size = requestedSize
        return copy
    }
    return NSImage(cgImage: output, size: requestedSize)
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
