import CoreGraphics
import Foundation
import ImageIO

actor RhythmArtworkPaletteCache {
    private struct Key: Hashable {
        let id: UUID
        let revision: Int
        let variant: ArtworkAssetVariant
    }

    private var palettes: [Key: RhythmAccentPalette] = [:]

    func palette(for asset: ArtworkAsset) async -> RhythmAccentPalette {
        let key = Key(
            id: asset.id,
            revision: asset.revision,
            variant: asset.variant
        )
        if let palette = palettes[key] {
            return palette
        }
        let data = asset.data
        let palette = await Task.detached(priority: .utility) {
            RhythmArtworkPaletteExtractor.extract(from: data)
                ?? .cadenceFallback
        }.value

        palettes[key] = palette
        return palette
    }
}

private enum RhythmArtworkPaletteExtractor {
    private struct Candidate {
        let color: RhythmPulseColor
        let score: Double
    }

    static func extract(from data: Data) -> RhythmAccentPalette? {
        guard let pixels = rgbaPixels(from: data) else {
            return nil
        }
        let candidates = accentCandidates(in: pixels)
        let selected = distinctColors(from: candidates)
        if selected.isEmpty {
            return neutralPalette(from: pixels)
        }
        guard !selected.isEmpty else {
            return nil
        }
        return RhythmAccentPalette(colors: selected)
    }

    private static func neutralPalette(
        from pixels: [UInt8]
    ) -> RhythmAccentPalette? {
        var buckets: [Int: Int] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha >= 0.5 else {
                continue
            }
            let color = RhythmPulseColor(
                red: Double(pixels[offset]) / 255,
                green: Double(pixels[offset + 1]) / 255,
                blue: Double(pixels[offset + 2]) / 255
            )
            guard color.saturation < 0.35 else {
                continue
            }
            let luminance = min(max(color.relativeLuminance, 0.38), 0.82)
            let key = Int((luminance * 10).rounded())
            buckets[key, default: 0] += 1
        }

        var luminances = buckets
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .map { Double($0.key) / 10 }
            .reduce(into: [Double]()) { selected, luminance in
                guard selected.allSatisfy({ abs($0 - luminance) >= 0.12 }) else {
                    return
                }
                selected.append(luminance)
            }
        for anchor in [0.38, 0.82, 0.6]
            where luminances.count < 5
            && luminances.allSatisfy({ abs($0 - anchor) >= 0.1 }) {
            luminances.append(anchor)
        }

        guard !luminances.isEmpty else {
            return nil
        }
        return RhythmAccentPalette(
            colors: luminances.map {
                RhythmPulseColor(red: $0, green: $0, blue: $0)
            }
        )
    }

    private static func rgbaPixels(from data: Data) -> [UInt8]? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let maximumDimension = 64
        let scale = min(
            1,
            Double(maximumDimension) / Double(max(image.width, image.height))
        )
        let width = max(Int(Double(image.width) * scale), 1)
        let height = max(Int(Double(image.height) * scale), 1)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private static func accentCandidates(
        in pixels: [UInt8]
    ) -> [Candidate] {
        var buckets: [Int: (color: RhythmPulseColor, count: Int)] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha >= 0.5 else {
                continue
            }
            let color = RhythmPulseColor(
                red: Double(pixels[offset]) / 255,
                green: Double(pixels[offset + 1]) / 255,
                blue: Double(pixels[offset + 2]) / 255
            )
            let brightness = max(color.red, color.green, color.blue)
            guard color.saturation >= 0.35, brightness >= 0.12 else {
                continue
            }
            let key = quantizedKey(for: color)
            if let existing = buckets[key] {
                buckets[key] = (existing.color, existing.count + 1)
            } else {
                buckets[key] = (color, 1)
            }
        }

        return buckets.values.map { bucket in
            Candidate(
                color: bucket.color,
                score: Double(bucket.count)
                    * (0.55 + bucket.color.saturation * 0.45)
            )
        }
        .sorted { $0.score > $1.score }
    }

    private static func distinctColors(
        from candidates: [Candidate]
    ) -> [RhythmPulseColor] {
        var selected: [RhythmPulseColor] = []
        for candidate in candidates {
            let isDistinct = selected.allSatisfy {
                colorDistance($0, candidate.color) >= 0.18
            }
            if isDistinct {
                selected.append(candidate.color)
            }
            if selected.count == 5 {
                break
            }
        }
        return selected
    }

    private static func quantizedKey(for color: RhythmPulseColor) -> Int {
        let red = Int(color.red * 7)
        let green = Int(color.green * 7)
        let blue = Int(color.blue * 7)
        return red << 8 | green << 4 | blue
    }

    private static func colorDistance(
        _ lhs: RhythmPulseColor,
        _ rhs: RhythmPulseColor
    ) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        return sqrt(red * red + green * green + blue * blue)
    }
}
