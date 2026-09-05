@testable import Cadence
import CoreGraphics
import QuartzCore
import Testing

struct RhythmPulseModelsTests {
    @Test("A hit creates three compact artwork-colored fields")
    func hitCreatesThreeCompactArtworkColoredFields() {
        var simulation = RhythmPulseSimulation()
        var random = SplitMix64(seed: 23)
        let artworkOrigin = CGPoint(x: 0.34, y: 0.38)

        simulation.registerHit(
            lane: .left,
            origin: artworkOrigin,
            palette: .fixture,
            time: 10,
            generator: &random
        )

        let washes = simulation.washes(at: 10.1)
        #expect(washes.count == 3)
        #expect(washes.allSatisfy { $0.center(at: 10) == artworkOrigin })
        #expect(Set(washes.map { $0.center(at: 10.1) }).count == 3)
        #expect(Set(washes.map(\.radius)).count == 3)
        #expect(washes.allSatisfy { $0.lifetime == 1.1 })
        #expect(
            washes.allSatisfy {
                RhythmAccentPalette.fixture.colors.contains($0.color)
            }
        )
    }

    @Test("Every field flashes from the artwork and travels outward")
    func everyLaneBurstsOutwardFromArtwork() {
        var leftSimulation = RhythmPulseSimulation()
        var rightSimulation = RhythmPulseSimulation()
        var leftRandom = SplitMix64(seed: 29)
        var rightRandom = SplitMix64(seed: 31)
        let leftOrigin = CGPoint(x: 0.34, y: 0.38)
        let rightOrigin = CGPoint(x: 0.66, y: 0.38)

        leftSimulation.registerHit(
            lane: .left,
            origin: leftOrigin,
            palette: .fixture,
            time: 0,
            generator: &leftRandom
        )
        rightSimulation.registerHit(
            lane: .right,
            origin: rightOrigin,
            palette: .fixture,
            time: 0,
            generator: &rightRandom
        )

        let leftWashes = leftSimulation.washes(at: 0.1)
        let rightWashes = rightSimulation.washes(at: 0.1)
        #expect(leftWashes.allSatisfy { $0.center(at: 0) == leftOrigin })
        #expect(rightWashes.allSatisfy { $0.center(at: 0) == rightOrigin })
        #expect(leftWashes.allSatisfy { $0.center(at: 0.1).x < leftOrigin.x })
        #expect(rightWashes.allSatisfy { $0.center(at: 0.1).x > rightOrigin.x })
        #expect(
            (leftWashes + rightWashes).allSatisfy {
                (0.06 ... 0.94).contains($0.destination.y)
                    && (0.12 ... 0.28).contains($0.radius)
                    && (0.82 ... 1.34).contains($0.horizontalScale)
                    && (0.7 ... 1.18).contains($0.verticalScale)
            }
        )
    }

    @Test("Repeated presses replace one lane within its fixed layer budget")
    func repeatedLaneHitReplacesItsColorFields() {
        var simulation = RhythmPulseSimulation()
        var random = SplitMix64(seed: 13)

        simulation.registerHit(
            lane: .left,
            origin: CGPoint(x: 0.34, y: 0.38),
            palette: .fixture,
            time: 0,
            generator: &random
        )
        let firstIDs = Set(simulation.washes(at: 0.1).map(\.id))
        simulation.registerHit(
            lane: .left,
            origin: CGPoint(x: 0.34, y: 0.38),
            palette: .fixture,
            time: 0.2,
            generator: &random
        )

        let replacementWashes = simulation.washes(at: 0.21)
        let replacementIDs = Set(replacementWashes.map(\.id))
        #expect(replacementWashes.count == 6)
        #expect(firstIDs.isSubset(of: replacementIDs))
        #expect(simulation.washes(at: 0.29).count == 3)
    }

    @Test("Opposite lanes can overlap with six color fields")
    func oppositeLanesOverlap() {
        var simulation = RhythmPulseSimulation()
        var random = SplitMix64(seed: 17)

        simulation.registerHit(
            lane: .left,
            origin: CGPoint(x: 0.34, y: 0.38),
            palette: .fixture,
            time: 0,
            generator: &random
        )
        simulation.registerHit(
            lane: .right,
            origin: CGPoint(x: 0.66, y: 0.38),
            palette: .fixture,
            time: 0.08,
            generator: &random
        )

        #expect(simulation.washes(at: 0.1).count == 6)
    }

    @Test("A thousand rapid hits keep the render workload bounded")
    func rapidHitStressKeepsTwelveFieldCeiling() {
        var simulation = RhythmPulseSimulation()
        var random = SplitMix64(seed: 41)

        for index in 0 ..< 1000 {
            simulation.registerHit(
                lane: index.isMultiple(of: 2) ? .left : .right,
                origin: CGPoint(
                    x: index.isMultiple(of: 2) ? 0.34 : 0.66,
                    y: 0.38
                ),
                palette: .fixture,
                time: Double(index) / 1000,
                generator: &random
            )
            #expect(simulation.allWashes.count <= 12)
        }
    }

    @Test("Color fields use the HTML impact timing and expansion")
    func washUsesHTMLImpactKinetics() throws {
        var simulation = RhythmPulseSimulation()
        var random = SplitMix64(seed: 37)
        simulation.registerHit(
            lane: .right,
            origin: CGPoint(x: 0.66, y: 0.38),
            palette: .fixture,
            time: 0,
            generator: &random
        )

        let wash = try #require(simulation.washes(at: 0.05).first)
        #expect(wash.opacity(at: 0) == 0)
        #expect(wash.opacity(at: 0.02) > wash.peakOpacity * 0.85)
        #expect(wash.opacity(at: 0.11) < wash.peakOpacity * 0.55)
        #expect(wash.opacity(at: 0.55) < wash.peakOpacity * 0.08)
        #expect(wash.scale(at: 0) == 0.2)
        #expect((0.88 ... 0.95).contains(wash.scale(at: 0.11)))
        #expect((1.4 ... 1.45).contains(wash.scale(at: 0.55)))
        #expect(wash.isAlive(at: 1.09))
        #expect(!wash.isAlive(at: 1.1))
    }

    @Test("Compositor samples the visible impact peak near twenty milliseconds")
    func compositorKeepsTheWashImpactPeak() throws {
        var simulation = RhythmPulseSimulation()
        var random = SplitMix64(seed: 39)
        simulation.registerHit(
            lane: .left,
            origin: CGPoint(x: 0.34, y: 0.38),
            palette: .fixture,
            time: 0,
            generator: &random
        )
        let wash = try #require(simulation.allWashes.first)

        let samples = RhythmPulseCompositorSampling.opacitySamples(for: wash)

        #expect(samples.count <= 7)
        #expect(samples.contains { (0.015 ... 0.025).contains($0.time) })
        #expect(
            samples.map(\.opacity).max() ?? 0
                > wash.peakOpacity * 0.85
        )
    }
}

private extension RhythmAccentPalette {
    static let fixture = RhythmAccentPalette(
        colors: [
            RhythmPulseColor(red: 0.86, green: 0.37, blue: 0.66),
            RhythmPulseColor(red: 0.49, green: 0.38, blue: 1),
            RhythmPulseColor(red: 0, green: 0.8, blue: 0.89),
        ]
    )
}

struct RhythmPulseCompositorTests {
    @MainActor
    @Test("Recycled compositor layers are hidden with neutral model state")
    func recycledLayersCannotFlashAtTheWindowOrigin() {
        let container = CALayer()
        let layer = CALayer()
        container.addSublayer(layer)
        layer.bounds = CGRect(x: 0, y: 0, width: 400, height: 220)
        layer.position = CGPoint(x: 17, y: 23)
        layer.opacity = 1
        layer.backgroundColor = CGColor(gray: 1, alpha: 1)
        layer.cornerRadius = 18
        layer.setAffineTransform(
            CGAffineTransform(rotationAngle: 0.7).scaledBy(x: 4, y: 3)
        )
        layer.add(CABasicAnimation(keyPath: "opacity"), forKey: "test")

        RhythmReusableLayer.prepareForReuse(layer)

        #expect(layer.superlayer == nil)
        #expect(layer.animationKeys() == nil)
        #expect(layer.isHidden)
        #expect(layer.opacity == 0)
        #expect(layer.bounds == .zero)
        #expect(layer.position == .zero)
        #expect(layer.backgroundColor == nil)
        #expect(layer.cornerRadius == 0)
        #expect(CATransform3DIsIdentity(layer.transform))
    }

    @MainActor
    @Test("Pooled compositor layers reset without rebuilding the layer tree")
    func pooledLayersStayAttachedWhileHidden() {
        let container = CALayer()
        let layer = CALayer()
        container.addSublayer(layer)
        layer.bounds = CGRect(x: 0, y: 0, width: 300, height: 180)
        layer.opacity = 1

        RhythmReusableLayer.prepareForReuse(
            layer,
            removeFromSuperlayer: false
        )

        #expect(layer.superlayer === container)
        #expect(layer.isHidden)
        #expect(layer.opacity == 0)
        #expect(layer.bounds == .zero)
    }

    @Test("HTML impact scale expands monotonically at render cadence")
    func washScaleExpandsMonotonically() throws {
        var simulation = RhythmPulseSimulation()
        var random = SplitMix64(seed: 43)
        simulation.registerHit(
            lane: .left,
            origin: CGPoint(x: 0.34, y: 0.38),
            palette: .fixture,
            time: 0,
            generator: &random
        )

        let wash = try #require(simulation.allWashes.first)
        let samples = (0 ... 66).map {
            wash.scale(at: Double($0) / 60)
        }
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("The pulse crosses the Lyrics divider without leaving Now Playing")
    func pulseFieldUsesWorkspaceBounds() {
        let layout = RhythmPulseLayout(
            workspaceWidth: 1439,
            panelStartX: 560
        )

        #expect(layout.clipRect.width == 1439)
        #expect(layout.intensity(atX: 559) > 0)
        #expect(layout.intensity(atX: 561) > 0)
        #expect(layout.intensity(atX: 1200) > 0)
        #expect(
            abs(layout.intensity(atX: 559) - layout.intensity(atX: 561))
                < 0.05
        )
    }

    @Test("Effect colors brighten without washing out artwork saturation")
    func effectColorsPreserveArtworkSaturation() {
        let darkPalette = RhythmAccentPalette(
            colors: [
                RhythmPulseColor(red: 0.08, green: 0.12, blue: 0.32),
                RhythmPulseColor(red: 0.16, green: 0.16, blue: 0.16),
            ]
        )
        let appearance = RhythmPulseAppearance.resolve(
            mode: .light,
            palette: darkPalette
        )

        let colorfulSource = darkPalette.colors[0]
        let colorfulEffect = appearance.colors[0]
        let neutralEffect = appearance.colors[1]

        #expect(colorfulEffect.saturation >= colorfulSource.saturation - 0.001)
        #expect(colorfulEffect.blue > colorfulEffect.green)
        #expect(colorfulEffect.green > colorfulEffect.red)
        #expect(
            max(colorfulEffect.red, colorfulEffect.green, colorfulEffect.blue)
                >= 0.82
        )
        #expect(neutralEffect.relativeLuminance >= 0.58)
        #expect(appearance.colors[1].saturation == 0)
        #expect(appearance.washBlendStrategy == .multiply)
        #expect(appearance.maximumWashAnimationFramesPerSecond == 60)
        #expect(!appearance.usesDarkBackdrop)
        #expect(!appearance.usesLiveBlur)
    }

    @Test("Cadence Mode background uses display-paced Metal motion")
    func cadenceModeBackgroundUsesDisplayPacedMetalMotion() {
        let appearance = CadenceModeBackgroundAppearance.resolve(
            reduceMotion: false,
            reduceTransparency: false,
            increasedContrast: false
        )

        #expect(appearance.isAnimated)
        #expect(appearance.maximumAnimationFramesPerSecond == 60)
    }

    @Test("A flat artwork accent expands into five shader colors")
    func flatArtworkStillProducesDynamicBackgroundZones() {
        let palette = RhythmAccentPalette(
            colors: [
                RhythmPulseColor(red: 0.72, green: 0.18, blue: 0.38),
            ]
        )

        let shaderColors = CadenceModeGradientReference.shaderColors(
            for: palette
        )

        #expect(shaderColors.count == 5)
        #expect(Set(shaderColors).count >= 4)
    }

    @Test("Cadence Mode background honors accessibility display settings")
    func cadenceModeBackgroundHonorsAccessibility() {
        let normal = CadenceModeBackgroundAppearance.resolve(
            reduceMotion: false,
            reduceTransparency: false,
            increasedContrast: false
        )
        let accessible = CadenceModeBackgroundAppearance.resolve(
            reduceMotion: true,
            reduceTransparency: true,
            increasedContrast: true
        )

        #expect(!accessible.isAnimated)
        #expect(normal.isAnimated)
    }
}
