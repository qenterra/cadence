import CoreImage
import SwiftUI

struct ProductionArtworkHaze: View {
    @Bindable var model: CadenceAppModel
    let artworkID: UUID?

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var palette: ArtworkHazePalette?

    var body: some View {
        Group {
            if let palette, !reduceTransparency {
                ZStack {
                    RadialGradient(
                        colors: [
                            palette.leading.opacity(leadingStrength),
                            palette.leading.opacity(leadingStrength * 0.42),
                            .clear,
                        ],
                        center: .topLeading,
                        startRadius: 18,
                        endRadius: 330
                    )
                    RadialGradient(
                        colors: [
                            palette.trailing.opacity(trailingStrength),
                            palette.trailing.opacity(trailingStrength * 0.42),
                            .clear,
                        ],
                        center: .bottomTrailing,
                        startRadius: 12,
                        endRadius: 310
                    )
                    LinearGradient(
                        colors: [
                            palette.leading.opacity(backgroundStrength),
                            palette.trailing.opacity(backgroundStrength * 0.84),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .saturation(colorScheme == .dark ? 1.12 : 1.28)
                .blur(radius: 44)
                .blendMode(colorScheme == .dark ? .plusLighter : .normal)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .task(id: artworkID) {
            palette = nil
            guard
                let artworkID,
                let asset = await model.librarySession.store.artworkAsset(
                    id: artworkID,
                    location: model.librarySession.location
                )
            else {
                return
            }
            let extractedPalette = await ArtworkHazePalette.extract(
                from: asset.data
            )
            guard !Task.isCancelled else {
                return
            }
            palette = extractedPalette
        }
    }

    private var leadingStrength: Double {
        colorScheme == .dark ? 0.48 : 0.62
    }

    private var trailingStrength: Double {
        colorScheme == .dark ? 0.40 : 0.54
    }

    private var backgroundStrength: Double {
        colorScheme == .dark ? 0.12 : 0.22
    }
}

private struct ArtworkHazePalette: Sendable {
    let leadingComponents: [Double]
    let trailingComponents: [Double]

    var leading: Color {
        color(leadingComponents)
    }

    var trailing: Color {
        color(trailingComponents)
    }

    static func extract(
        from data: Data
    ) async -> ArtworkHazePalette? {
        await Task.detached(priority: .utility) {
            guard let image = CIImage(data: data) else {
                return nil
            }
            let extent = image.extent.integral
            guard !extent.isEmpty else {
                return nil
            }
            let midpoint = extent.midX
            let leading = CGRect(
                x: extent.minX,
                y: extent.minY,
                width: midpoint - extent.minX,
                height: extent.height
            )
            let trailing = CGRect(
                x: midpoint,
                y: extent.minY,
                width: extent.maxX - midpoint,
                height: extent.height
            )
            guard
                let first = average(image, extent: leading),
                let second = average(image, extent: trailing)
            else {
                return nil
            }
            return ArtworkHazePalette(
                leadingComponents: first,
                trailingComponents: second
            )
        }.value
    }

    private static func average(
        _ image: CIImage,
        extent: CGRect
    ) -> [Double]? {
        guard
            let filter = CIFilter(name: "CIAreaAverage")
        else {
            return nil
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(
                output,
                toBitmap: &bytes,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        return bytes.map { Double($0) / 255 }
    }

    private func color(
        _ components: [Double]
    ) -> Color {
        guard components.count == 4 else {
            return .clear
        }
        return Color(
            red: components[0],
            green: components[1],
            blue: components[2]
        )
    }
}
