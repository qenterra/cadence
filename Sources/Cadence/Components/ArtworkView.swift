import AppKit
import ImageIO
import QenTerraMediaComponents
import SwiftUI

struct ArtworkView: View {
    let palette: ArtworkPalette
    let title: String
    var cornerRadius: CGFloat = 8
    var showsBorder = true
    var fillsAvailableSpace = false

    var body: some View {
        ArtworkSurface(
            state: .content,
            title: title,
            cornerRadius: cornerRadius,
            showsBorder: showsBorder,
            fillsAvailableSpace: fillsAvailableSpace
        ) {
            QenTerraMediaComponents.ArtworkPlaceholder(
                palette: palette.designSystemPalette
            )
        }
    }
}

struct MediaArtworkView: View {
    let source: ResolvedArtworkSource
    let title: String
    let placeholder: ArtworkPlaceholder
    var cornerRadius: CGFloat = 8
    var showsBorder = true
    var fillsAvailableSpace = false

    var body: some View {
        ArtworkSurface(
            state: CadenceMediaAdapters.artworkState(for: source),
            title: title,
            cornerRadius: cornerRadius,
            showsBorder: showsBorder,
            fillsAvailableSpace: fillsAvailableSpace
        ) {
            readyContent
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        switch source {
        case let .catalog(palette):
            QenTerraMediaComponents.ArtworkPlaceholder(
                palette: palette.designSystemPalette
            )
        case let .custom(asset):
            CustomArtworkContent(asset: asset, placeholder: placeholder)
        case .placeholder:
            EmptyView()
        }
    }
}

private struct CustomArtworkContent: View {
    let asset: ArtistImageAsset
    let placeholder: ArtworkPlaceholder
    @State private var image: CGImage?
    @State private var activeCacheKey: ArtworkImageCacheKey?
    @State private var loadedCacheKey: ArtworkImageCacheKey?

    var body: some View {
        Group {
            if let image, loadedCacheKey == assetCacheKey {
                GeometryReader { geometry in
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .scaleEffect(asset.scale)
                        .offset(
                            x: asset.normalizedOffset.width * geometry.size.width,
                            y: asset.normalizedOffset.height * geometry.size.height
                        )
                        .clipped()
                }
            } else {
                QenTerraMediaComponents.ArtworkPlaceholder(
                    kind: placeholder.designSystemKind
                )
            }
        }
        .task(id: assetCacheKey) {
            let requestedKey = assetCacheKey
            activeCacheKey = requestedKey
            image = nil
            loadedCacheKey = nil
            guard !Task.isCancelled else { return }
            let decodedImage = await ArtworkImageCache.shared.image(for: asset)
            guard !Task.isCancelled, activeCacheKey == requestedKey else { return }
            image = decodedImage
            loadedCacheKey = requestedKey
        }
    }

    private var assetCacheKey: ArtworkImageCacheKey {
        ArtworkImageCacheKey(
            id: asset.id,
            revision: asset.revision,
            variant: asset.variant
        )
    }
}

struct ArtworkImageCacheKey: Hashable, Sendable {
    let id: UUID
    let revision: Int
    let variant: ArtworkAssetVariant
}

struct ArtworkImageCacheMetrics: Equatable, Sendable {
    let decodeInvocations: Int
}

enum ArtworkImageDecoder {
    static func image(for asset: ArtworkAsset) -> CGImage? {
        guard
            let source = CGImageSourceCreateWithData(asset.data as CFData, nil)
        else {
            return nil
        }
        switch asset.variant {
        case .original:
            return CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        case .thumbnail, .trackRow:
            guard let maximumPixelDimension = asset.variant
                .maximumPixelDimension else {
                return nil
            }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize:
                    maximumPixelDimension,
            ] as CFDictionary)
        }
    }

    static func decodedByteCost(of image: CGImage) -> Int {
        let (pixels, pixelOverflow) = image.width.multipliedReportingOverflow(
            by: image.height
        )
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow else {
            return .max
        }
        return max(bytes, 0)
    }
}

actor ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let cache = NSCache<NSString, CGImage>()
    private(set) var decodeInvocations = 0

    init(
        countLimit: Int = 80,
        totalCostLimit: Int = 128 * 1024 * 1024
    ) {
        cache.countLimit = max(countLimit, 1)
        cache.totalCostLimit = max(totalCostLimit, 1)
    }

    func image(for asset: ArtworkAsset) -> CGImage? {
        let typedKey = ArtworkImageCacheKey(
            id: asset.id,
            revision: asset.revision,
            variant: asset.variant
        )
        let key = Self.cacheKey(for: typedKey)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard !Task.isCancelled else {
            return nil
        }
        decodeInvocations += 1
        guard let image = ArtworkImageDecoder.image(for: asset) else {
            return nil
        }
        let pixelCost = ArtworkImageDecoder.decodedByteCost(of: image)
        guard
            pixelCost != .max,
            pixelCost <= cache.totalCostLimit
        else {
            return image
        }
        cache.setObject(
            image,
            forKey: key,
            cost: pixelCost
        )
        return image
    }

    func metrics() -> ArtworkImageCacheMetrics {
        ArtworkImageCacheMetrics(decodeInvocations: decodeInvocations)
    }

    private static func cacheKey(
        for key: ArtworkImageCacheKey
    ) -> NSString {
        "\(key.id.uuidString)-\(key.revision)-\(key.variant)" as NSString
    }
}
