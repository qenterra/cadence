import AppKit
import ImageIO
import MediaPlayer

@MainActor
protocol SystemMediaArtworkProviding: AnyObject {
    func artwork(for id: UUID) async -> MPMediaItemArtwork?
}

struct SystemMediaArtworkImageSource: Sendable {
    let data: Data
    let boundsSize: NSSize

    init?(data: Data) {
        guard
            let source = Self.makeImageSource(from: data),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        self.data = data
        boundsSize = Self.logicalSize(
            of: image,
            from: source
        )
    }

    func image(at requestedSize: NSSize) -> NSImage? {
        guard let source = Self.decodeImage(from: data) else {
            return nil
        }
        let outputSize = resolvedSize(for: requestedSize)
        guard outputSize != boundsSize else {
            return NSImage(cgImage: source, size: outputSize)
        }
        return resizedImage(
            source,
            requestedSize: outputSize
        )
    }

    private func resolvedSize(for requestedSize: NSSize) -> NSSize {
        guard requestedSize.width > 0, requestedSize.height > 0 else {
            return boundsSize
        }
        return requestedSize
    }

    private func resizedImage(
        _ source: CGImage,
        requestedSize: NSSize
    ) -> NSImage {
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
            return NSImage(cgImage: source, size: requestedSize)
        }
        context.interpolationQuality = .high
        context.draw(
            source,
            in: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(pixelWidth),
                height: CGFloat(pixelHeight)
            )
        )
        guard let output = context.makeImage() else {
            return NSImage(cgImage: source, size: requestedSize)
        }
        return NSImage(cgImage: output, size: requestedSize)
    }

    private static func decodeImage(from data: Data) -> CGImage? {
        guard let source = makeImageSource(from: data) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func makeImageSource(from data: Data) -> CGImageSource? {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                nil
            ),
            CGImageSourceGetType(source) != nil
        else {
            return nil
        }
        return source
    }

    private static func logicalSize(
        of image: CGImage,
        from source: CGImageSource
    ) -> NSSize {
        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any]
        let pixelWidth = dimension(
            for: kCGImagePropertyPixelWidth,
            in: properties,
            fallback: image.width
        )
        let pixelHeight = dimension(
            for: kCGImagePropertyPixelHeight,
            in: properties,
            fallback: image.height
        )
        let dpiWidth = dimension(
            for: kCGImagePropertyDPIWidth,
            in: properties,
            fallback: 72
        )
        let dpiHeight = dimension(
            for: kCGImagePropertyDPIHeight,
            in: properties,
            fallback: 72
        )
        return NSSize(
            width: pixelWidth * 72 / dpiWidth,
            height: pixelHeight * 72 / dpiHeight
        )
    }

    private static func dimension(
        for key: CFString,
        in properties: [CFString: Any]?,
        fallback: Int
    ) -> CGFloat {
        guard
            let value = properties?[key] as? NSNumber,
            value.doubleValue > 0
        else {
            return CGFloat(fallback)
        }
        return CGFloat(value.doubleValue)
    }
}

private func makeSystemMediaArtwork(
    source: SystemMediaArtworkImageSource
) -> MPMediaItemArtwork {
    MPMediaItemArtwork(
        boundsSize: source.boundsSize
    ) { requestedSize in
        source.image(at: requestedSize)
            ?? NSImage(size: source.boundsSize)
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

        guard let source = SystemMediaArtworkImageSource(data: asset.data) else {
            return nil
        }
        let artwork = makeSystemMediaArtwork(
            source: source
        )
        cache = cache.filter { $0.key.id != id }
        cache[key] = artwork
        return artwork
    }
}
