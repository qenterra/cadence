import AppKit
@testable import Cadence
import Testing

struct RhythmArtworkPaletteTests {
    @MainActor
    @Test("A fresh pulse store can render before artwork extraction finishes")
    func pulseStoreStartsWithProductFallback() {
        let store = RhythmPulseStore()

        store.registerHit(lane: .left)

        #expect(store.palette == .cadenceFallback)
        #expect(!store.renderWashes.isEmpty)
        #expect(!store.renderParticles.isEmpty)
    }

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

        let palette = await RhythmArtworkPaletteCache().palette(for: asset)

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

    @Test("Grayscale artwork keeps a visible neutral palette")
    func grayscaleKeepsNeutralPalette() async throws {
        let asset = try ArtworkAsset(
            data: makePNG(
                colors: [
                    NSColor(
                        deviceRed: 0.25,
                        green: 0.25,
                        blue: 0.25,
                        alpha: 1
                    ),
                    NSColor(
                        deviceRed: 0.65,
                        green: 0.65,
                        blue: 0.65,
                        alpha: 1
                    ),
                ]
            )
        )

        let palette = await RhythmArtworkPaletteCache().palette(for: asset)

        #expect(palette.colors.count >= 3)
        #expect(palette.colors.allSatisfy { $0.saturation == 0 })
        #expect(
            palette.colors.allSatisfy {
                (0.32 ... 0.82).contains($0.relativeLuminance)
            }
        )
        let luminances = palette.colors.map(\.relativeLuminance)
        #expect(
            (luminances.max() ?? 0) - (luminances.min() ?? 0) >= 0.34
        )
    }

    @Test("Unreadable artwork uses the deterministic Cadence palette")
    func unreadableArtworkUsesProductFallback() async {
        let asset = ArtworkAsset(data: Data("not an image".utf8))

        let palette = await RhythmArtworkPaletteCache().palette(for: asset)

        #expect(palette == .cadenceFallback)
        #expect(!palette.colors.isEmpty)
    }

    @MainActor
    @Test("Missing artwork still prepares effects")
    func missingArtworkUsesProductFallback() async {
        let store = RhythmPulseStore()

        await store.prepare(asset: nil)

        #expect(store.palette == .cadenceFallback)
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
