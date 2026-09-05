import AppKit
@testable import Cadence
import MetalKit
import simd
import Testing

struct CadenceModeBackgroundContrastTests {
    @Test("Cadence Mode contrast follows palette luminance")
    func contrastFollowsPaletteLuminance() {
        let cases: [(RhythmAccentPalette, Double)] = [
            (
                RhythmAccentPalette(colors: [
                    RhythmPulseColor(red: 0, green: 0, blue: 0),
                ]),
                0.10
            ),
            (
                RhythmAccentPalette(colors: [
                    RhythmPulseColor(red: 0.5, green: 0.5, blue: 0.5),
                ]),
                0.16
            ),
            (
                RhythmAccentPalette(colors: [
                    RhythmPulseColor(red: 1, green: 1, blue: 1),
                ]),
                0.22
            ),
        ]

        for (palette, expectedOpacity) in cases {
            #expect(
                abs(
                    CadenceModeBackgroundContrast.opacity(for: palette)
                        - expectedOpacity
                ) <= 0.000_001
            )
        }

        #expect(
            CadenceModeBackgroundContrast.opacity(
                for: RhythmAccentPalette(colors: [])
            ) == CadenceModeBackgroundContrast.opacity(
                for: .cadenceFallback
            )
        )
    }

    @Test("Live effects reach one bounded background darkness")
    func liveEffectsReachBoundedBackgroundDarkness() {
        let palettes = [
            RhythmAccentPalette(colors: [
                RhythmPulseColor(red: 0, green: 0, blue: 0),
            ]),
            RhythmAccentPalette(colors: [
                RhythmPulseColor(red: 0.5, green: 0.5, blue: 0.5),
            ]),
            RhythmAccentPalette(colors: [
                RhythmPulseColor(red: 1, green: 1, blue: 1),
            ]),
        ]

        for palette in palettes {
            let idleOpacity = CadenceModeBackgroundContrast.opacity(
                for: palette
            )
            let tintOpacity = CadenceModeBackgroundContrast
                .activeTintOpacity(for: palette)
            let combinedOpacity = 1
                - (1 - idleOpacity) * (1 - tintOpacity)

            #expect(abs(combinedOpacity - 0.62) <= 0.000_001)
        }
    }

    @Test("Active tint keeps the darkest artwork hue")
    func activeTintKeepsDarkestArtworkHue() {
        let tint = CadenceModeBackgroundContrast.tint(
            for: RhythmAccentPalette(colors: [
                RhythmPulseColor(red: 1, green: 1, blue: 1),
                RhythmPulseColor(red: 0, green: 0, blue: 0.5),
            ])
        )

        #expect(abs(tint.red) <= 0.000_001)
        #expect(abs(tint.green) <= 0.000_001)
        #expect(abs(tint.blue - 0.14) <= 0.000_001)
        #expect(
            CadenceModeBackgroundContrast.tint(
                for: RhythmAccentPalette(colors: [])
            ) == CadenceModeBackgroundContrast.tint(
                for: .cadenceFallback
            )
        )
    }

    @Test("Tint darkening and brightening share one smooth duration")
    func tintTransitionsAreSymmetric() {
        #expect(
            CadenceModeBackgroundContrast.transitionDuration(
                hasLiveEffects: true,
                reduceMotion: false
            ) == 1.4
        )
        #expect(
            CadenceModeBackgroundContrast.transitionDuration(
                hasLiveEffects: false,
                reduceMotion: false
            ) == 1.4
        )
        #expect(
            CadenceModeBackgroundContrast.transitionDuration(
                hasLiveEffects: false,
                reduceMotion: true
            ) == 0.1
        )
    }
}

struct CadenceModeGradientTests {
    @Test("Cadence Mode gradient reproduces the reference plane topology")
    func reproducesReferencePlaneTopology() {
        let mesh = CadenceModeGradientReference.makeMesh()

        #expect(mesh.vertices.count == 40401)
        #expect(mesh.indices.count == 240_000)
        #expect(mesh.vertices[0].position == SIMD3<Float>(-0.75, 0.75, 0))
        #expect(mesh.vertices[0].textureCoordinate == SIMD2<Float>(0, 1))
        #expect(mesh.vertices[200].position == SIMD3<Float>(0.75, 0.75, 0))
        #expect(mesh.vertices[40400].position == SIMD3<Float>(0.75, -0.75, 0))
        #expect(
            Array(mesh.indices.prefix(6))
                == [0, 201, 1, 201, 202, 1]
        )
    }

    @Test("Artwork accents become five linear Metal shader colors")
    func artworkAccentsBecomeFiveLinearMetalShaderColors() {
        let palette = RhythmAccentPalette(
            colors: [
                RhythmPulseColor(red: 1, green: 0, blue: 0),
                RhythmPulseColor(red: 0, green: 1, blue: 0),
                RhythmPulseColor(red: 0, green: 0, blue: 1),
            ]
        )

        let colors = CadenceModeGradientReference.shaderColors(for: palette)
        let linearHalf: Float = 0.214_041_14

        #expect(colors.count == 5)
        #expect(colors[0] == SIMD3<Float>(1, 0, 0))
        #expect(
            approximatelyEqual(
                colors[1],
                SIMD3<Float>(linearHalf, linearHalf, 0)
            )
        )
        #expect(colors[2] == SIMD3<Float>(0, 1, 0))
        #expect(
            approximatelyEqual(
                colors[3],
                SIMD3<Float>(0, linearHalf, linearHalf)
            )
        )
        #expect(colors[4] == SIMD3<Float>(0, 0, 1))
    }

    @Test("Reference camera centers the mesh and covers a widescreen frame")
    func referenceCameraCoversWidescreenFrame() {
        let modelMatrix = CadenceModeGradientReference.modelMatrix
        let viewProjection = CadenceModeGradientReference
            .viewProjectionMatrix(aspectRatio: 16 / 9)
        let center = viewProjection * modelMatrix * SIMD4<Float>(0, 0, 0, 1)
        let farCorner = viewProjection * modelMatrix
            * SIMD4<Float>(-0.75, 0.75, 0, 1)
        let centerNDC = center / center.w
        let cornerNDC = farCorner / farCorner.w

        #expect(abs(centerNDC.x) <= 0.000_001)
        #expect(abs(centerNDC.y) <= 0.000_001)
        #expect(cornerNDC.x < -1)
        #expect(cornerNDC.y > 1)
    }

    @Test("Reduced motion freezes the gradient shader clock")
    func reducedMotionFreezesGradientShaderClock() {
        #expect(
            CadenceModeGradientTimeline.elapsedTime(
                startedAt: 10,
                currentTime: 14.5,
                isAnimated: true
            ) == 4.5
        )
        #expect(
            CadenceModeGradientTimeline.elapsedTime(
                startedAt: 10,
                currentTime: 14.5,
                isAnimated: false
            ) == 0
        )
    }

    @MainActor
    @Test(
        "Cadence Mode background is a Metal surface that honors motion",
        .appKitExclusive
    )
    func backgroundIsMetalAndHonorsMotion() {
        let view = makeView()
        let animated = CadenceModeBackgroundAppearance.resolve(
            reduceMotion: false,
            reduceTransparency: false,
            increasedContrast: false
        )
        view.update(palette: Self.referencePalette, appearance: animated)

        #expect(view.device != nil)
        #expect(view.delegate != nil)
        #expect(view.isPaused == false)

        let reduced = CadenceModeBackgroundAppearance.resolve(
            reduceMotion: true,
            reduceTransparency: false,
            increasedContrast: false
        )
        view.update(palette: Self.referencePalette, appearance: reduced)
        #expect(view.isPaused == true)
    }

    @MainActor
    @Test(
        "Metal gradient renders a chromatic terrain frame",
        .appKitExclusive
    )
    func rendersChromaticTerrainFrame() {
        let view = makeView()
        view.update(
            palette: Self.referencePalette,
            appearance: .resolve(
                reduceMotion: true,
                reduceTransparency: false,
                increasedContrast: false
            )
        )

        guard let image = view.makeSnapshot(
            size: CGSize(width: 640, height: 360),
            time: 0
        ) else {
            Issue.record("Metal renderer did not produce a snapshot")
            return
        }
        let samples = colorSamples(in: image)

        #expect(image.width == 640)
        #expect(image.height == 360)
        #expect(samples.colors.count > 32)
        #expect(samples.chromaticCount > 100)
    }

    @MainActor
    @Test(
        "Reference palette keeps both warm and cool terrain bands",
        .appKitExclusive
    )
    func referencePaletteKeepsWarmAndCoolTerrainBands() {
        let view = makeView()
        view.update(
            palette: Self.referencePalette,
            appearance: .resolve(
                reduceMotion: true,
                reduceTransparency: false,
                increasedContrast: false
            )
        )

        guard let image = view.makeSnapshot(
            size: CGSize(width: 640, height: 360),
            time: 1.2
        ) else {
            Issue.record("Metal renderer did not produce a reference snapshot")
            return
        }
        let samples = colorSamples(in: image)

        #expect(samples.warmCount > 100)
        #expect(samples.coolCount > 50)
    }
}

private extension CadenceModeGradientTests {
    struct Samples {
        var colors: Set<UInt32> = []
        var chromaticCount = 0
        var warmCount = 0
        var coolCount = 0
    }

    @MainActor
    func makeView() -> CadenceModeBackgroundView {
        CadenceModeBackgroundView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 360),
            device: MTLCreateSystemDefaultDevice()
        )
    }

    func colorSamples(in image: CGImage) -> Samples {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var samples = Samples()
        for row in stride(from: 0, to: bitmap.pixelsHigh, by: 12) {
            for column in stride(from: 0, to: bitmap.pixelsWide, by: 12) {
                guard let color = bitmap.colorAt(x: column, y: row)?
                    .usingColorSpace(.deviceRGB) else {
                    continue
                }
                let red = UInt32((color.redComponent * 255).rounded())
                let green = UInt32((color.greenComponent * 255).rounded())
                let blue = UInt32((color.blueComponent * 255).rounded())
                samples.colors.insert((red << 16) | (green << 8) | blue)
                if max(red, green, blue) - min(red, green, blue) > 12 {
                    samples.chromaticCount += 1
                }
                if color.redComponent > color.blueComponent + 0.05 {
                    samples.warmCount += 1
                }
                if color.blueComponent > color.redComponent + 0.05 {
                    samples.coolCount += 1
                }
            }
        }
        return samples
    }

    static let referencePalette = RhythmAccentPalette(colors: [
        RhythmPulseColor(red: 0x8E / 255, green: 0xCA / 255, blue: 0xE6 / 255),
        RhythmPulseColor(red: 0x21 / 255, green: 0x9E / 255, blue: 0xBC / 255),
        RhythmPulseColor(red: 0x02 / 255, green: 0x30 / 255, blue: 0x47 / 255),
        RhythmPulseColor(red: 0xFF / 255, green: 0xB7 / 255, blue: 0x03 / 255),
        RhythmPulseColor(red: 0xFB / 255, green: 0x85 / 255, blue: 0),
    ])
}

private func approximatelyEqual(
    _ lhs: SIMD3<Float>,
    _ rhs: SIMD3<Float>,
    tolerance: Float = 0.000_001
) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance
        && abs(lhs.y - rhs.y) <= tolerance
        && abs(lhs.z - rhs.z) <= tolerance
}
