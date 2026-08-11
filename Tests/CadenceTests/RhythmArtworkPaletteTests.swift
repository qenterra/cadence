import AppKit
@testable import Cadence
import Testing

struct RhythmArtworkPaletteTests {
    @Test("Palette extraction returns saturated artwork accents")
    func extractsArtworkAccents() async throws {
        let pink = NSColor(
            calibratedRed: 0.86,
            green: 0.37,
            blue: 0.66,
            alpha: 1
        )
        let cyan = NSColor(
            calibratedRed: 0,
            green: 0.8,
            blue: 0.89,
            alpha: 1
        )
        let nearBlack = NSColor(
            calibratedRed: 0.05,
            green: 0.05,
            blue: 0.08,
            alpha: 1
        )
        let asset = try ArtworkAsset(
            data: makePNG(colors: [pink, cyan, nearBlack])
        )

        let palette = try #require(
            await RhythmArtworkPaletteCache().palette(for: asset)
        )

        #expect(palette.colors.allSatisfy { $0.saturation >= 0.35 })
        #expect(
            palette.colors.contains {
                $0.isNear(red: 0.86, green: 0.37, blue: 0.66)
            }
        )
        #expect(
            palette.colors.contains {
                $0.isNear(red: 0, green: 0.8, blue: 0.89)
            }
        )
    }

    @Test("Grayscale artwork does not invent accent colors")
    func grayscaleHasNoAccentPalette() async throws {
        let asset = try ArtworkAsset(
            data: makePNG(
                colors: [
                    NSColor(calibratedWhite: 0.25, alpha: 1),
                    NSColor(calibratedWhite: 0.65, alpha: 1),
                ]
            )
        )

        #expect(
            await RhythmArtworkPaletteCache().palette(for: asset) == nil
        )
    }

    private func makePNG(colors: [NSColor]) throws -> Data {
        let width = colors.count * 12
        let height = 12
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            )
        )

        for (index, color) in colors.enumerated() {
            for horizontalIndex in (index * 12) ..< ((index + 1) * 12) {
                for verticalIndex in 0 ..< height {
                    representation.setColor(
                        color,
                        atX: horizontalIndex,
                        y: verticalIndex
                    )
                }
            }
        }

        return try #require(
            representation.representation(
                using: .png,
                properties: [:]
            )
        )
    }
}
