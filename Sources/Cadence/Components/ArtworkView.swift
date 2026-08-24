import AppKit
import ImageIO
import SwiftUI

struct ArtworkView: View {
    let palette: ArtworkPalette
    let title: String
    var cornerRadius: CGFloat = 8
    var showsBorder = true
    var fillsAvailableSpace = false

    var body: some View {
        if fillsAvailableSpace {
            artwork
        } else {
            artwork
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private var artwork: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: palette.colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(palette.highlight.opacity(0.52))
                    .frame(
                        width: geometry.size.width * 0.72,
                        height: geometry.size.height * 0.72
                    )
                    .blur(radius: geometry.size.width * 0.12)
                    .offset(
                        x: geometry.size.width * 0.2,
                        y: -geometry.size.height * 0.18
                    )

                LinearGradient(
                    colors: [.clear, .black.opacity(0.42)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Image(systemName: palette.symbolName)
                    .font(.system(size: symbolSize(for: geometry.size), weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.62))
                    .symbolRenderingMode(.hierarchical)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Artwork for \(title)")
    }

    private func symbolSize(for size: CGSize) -> CGFloat {
        min(max(size.width * 0.18, 10), 34)
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
        Group {
            switch source {
            case let .catalog(palette):
                ArtworkView(
                    palette: palette,
                    title: title,
                    cornerRadius: cornerRadius,
                    showsBorder: showsBorder,
                    fillsAvailableSpace: fillsAvailableSpace
                )
            case let .custom(asset):
                CustomArtworkContent(
                    asset: asset,
                    placeholder: placeholder,
                    cornerRadius: cornerRadius,
                    showsBorder: showsBorder
                )
            case let .placeholder(kind):
                ArtworkPlaceholderView(
                    kind: kind,
                    cornerRadius: cornerRadius,
                    showsBorder: showsBorder
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Artwork for \(title)")
    }
}

private struct CustomArtworkContent: View {
    let asset: ArtistImageAsset
    let placeholder: ArtworkPlaceholder
    let cornerRadius: CGFloat
    let showsBorder: Bool
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
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    if showsBorder {
                        RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .continuous
                        )
                        .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
                    }
                }
            } else {
                ArtworkPlaceholderView(
                    kind: placeholder,
                    cornerRadius: cornerRadius,
                    showsBorder: showsBorder
                )
            }
        }
        .task(id: assetCacheKey) {
            let requestedKey = assetCacheKey
            activeCacheKey = requestedKey
            image = nil
            loadedCacheKey = nil
            guard !Task.isCancelled else {
                return
            }
            let decodedImage = await ArtworkImageCache.shared.image(for: asset)
            guard
                !Task.isCancelled,
                activeCacheKey == requestedKey
            else {
                return
            }
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

private struct ArtworkPlaceholderView: View {
    let kind: ArtworkPlaceholder
    let cornerRadius: CGFloat
    let showsBorder: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CadenceTheme.secondarySurface

                Image(systemName: kind.symbolName)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .padding(
                        min(geometry.size.width, geometry.size.height)
                            * placeholderPadding
                    )
                    .offset(
                        x: kind == .artist
                            ? min(
                                geometry.size.width,
                                geometry.size.height
                            ) * 0.013
                            : 0
                    )
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            if showsBorder {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
    }

    private var placeholderPadding: CGFloat {
        switch kind {
        case .artist:
            0.2
        case .album, .playlist, .smartCollection:
            0.26
        case .track:
            0.3
        }
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

private extension ArtworkPalette {
    var colors: [Color] {
        switch self {
        case .amberNoir: [Color(red: 0.08, green: 0.06, blue: 0.04), Color(red: 0.75, green: 0.42, blue: 0.12)]
        case .arctic: [Color(red: 0.10, green: 0.20, blue: 0.30), Color(red: 0.62, green: 0.86, blue: 0.94)]
        case .blueHour: [Color(red: 0.03, green: 0.08, blue: 0.18), Color(red: 0.14, green: 0.38, blue: 0.74)]
        case .ember: [Color(red: 0.12, green: 0.03, blue: 0.03), Color(red: 0.86, green: 0.24, blue: 0.10)]
        case .forest: [Color(red: 0.03, green: 0.12, blue: 0.09), Color(red: 0.26, green: 0.58, blue: 0.38)]
        case .lilac: [Color(red: 0.15, green: 0.10, blue: 0.22), Color(red: 0.58, green: 0.42, blue: 0.72)]
        case .ocean: [Color(red: 0.02, green: 0.13, blue: 0.18), Color(red: 0.08, green: 0.52, blue: 0.64)]
        case .rose: [Color(red: 0.18, green: 0.06, blue: 0.10), Color(red: 0.74, green: 0.27, blue: 0.40)]
        case .silver: [Color(red: 0.12, green: 0.13, blue: 0.15), Color(red: 0.60, green: 0.64, blue: 0.68)]
        case .sunset: [Color(red: 0.18, green: 0.06, blue: 0.16), Color(red: 0.92, green: 0.38, blue: 0.20)]
        }
    }

    var highlight: Color {
        colors.last ?? .white
    }

    var symbolName: String {
        switch self {
        case .amberNoir: "waveform"
        case .arctic: "snowflake"
        case .blueHour: "moonphase.waning.crescent"
        case .ember: "sparkles"
        case .forest: "leaf"
        case .lilac: "circle.hexagongrid"
        case .ocean: "water.waves"
        case .rose: "camera.macro"
        case .silver: "circle.grid.cross"
        case .sunset: "sun.horizon"
        }
    }
}
