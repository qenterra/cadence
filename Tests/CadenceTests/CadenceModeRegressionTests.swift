import AppKit
@testable import Cadence
import QuartzCore
import Testing

struct CadenceModeRegressionTests {
    @Test("Bass response stays subtle and becomes static with Reduce Motion")
    func bassResponseIsBounded() {
        let idle = CadenceModeBassResponse.resolve(
            level: 0,
            reduceMotion: false
        )
        let peak = CadenceModeBassResponse.resolve(
            level: 1,
            reduceMotion: false
        )
        let reduced = CadenceModeBassResponse.resolve(
            level: 1,
            reduceMotion: true
        )

        #expect(idle.artworkScale == 1)
        #expect(peak.artworkScale > idle.artworkScale)
        #expect(peak.artworkScale <= 1.05)
        #expect(peak.haloOpacity <= 0.22)
        #expect(reduced == .identity)
    }

    @Test("Low-frequency energy drives the meter more than upper mids")
    func bassFilterPrefersLowFrequencies() {
        let sampleRate = 48000.0
        let frameCount = 4800
        let bass = (0 ..< frameCount).map { frame in
            Float(sin(2 * Double.pi * 80 * Double(frame) / sampleRate) * 0.35)
        }
        let upperMid = (0 ..< frameCount).map { frame in
            Float(sin(2 * Double.pi * 1200 * Double(frame) / sampleRate) * 0.35)
        }

        var bassFilter = PCMBassEnergyFilter(sampleRate: sampleRate)
        var upperMidFilter = PCMBassEnergyFilter(sampleRate: sampleRate)

        let bassLevel = bassFilter.process(samples: bass)
        let upperMidLevel = upperMidFilter.process(samples: upperMid)

        #expect(bassLevel > upperMidLevel * 2)
        #expect((0 ... 1).contains(bassLevel))
    }

    @Test("Precomputed bass envelopes interpolate for native routes")
    func bassEnvelopeInterpolation() {
        let envelope = PlaybackBassEnvelope(
            samplesPerSecond: 2,
            levels: [0, 1, 0]
        )

        #expect(envelope.level(at: 0) == 0)
        #expect(envelope.level(at: 0.25) == 0.5)
        #expect(envelope.level(at: 0.5) == 1)
        #expect(envelope.level(at: 10) == 0)
    }

    @Test("Unavailable lyrics reserve display-scale type for the track")
    func unavailableLyricsTypography() {
        #expect(CadenceModeUnavailableLyricsMetrics.titleSize >= 32)
        #expect(
            CadenceModeUnavailableLyricsMetrics.titleSize
                > CadenceModeUnavailableLyricsMetrics.artistSize
        )
    }

    @Test("Cadence Mode keeps a hard 60 FPS floor and 110 FPS ProMotion target")
    func performancePolicyKeepsSupportedFloor() {
        #expect(
            CadenceModePerformancePolicy.minimumDeliveredFramesPerSecond(
                displayMaximumFramesPerSecond: 60
            ) == 60
        )
        #expect(
            CadenceModePerformancePolicy.minimumDeliveredFramesPerSecond(
                displayMaximumFramesPerSecond: 120
            ) == 110
        )
        #expect(CadenceModePerformancePolicy.maximumFrameDuration <= 0.025)
        #expect(CadenceModePerformancePolicy.maximumInputLatency <= 0.010)
        let sixtyHertzRange = CadenceModePerformancePolicy
            .animationFrameRateRange(displayMaximumFramesPerSecond: 60)
        let proMotionRange = CadenceModePerformancePolicy
            .animationFrameRateRange(displayMaximumFramesPerSecond: 120)
        let backgroundRange = CadenceModePerformancePolicy
            .animationFrameRateRange(
                displayMaximumFramesPerSecond: 120,
                contentMaximumFramesPerSecond: 60
            )
        #expect(sixtyHertzRange.minimum == 60)
        #expect(sixtyHertzRange.preferred == 60)
        #expect(proMotionRange.minimum == 60)
        #expect(proMotionRange.preferred == 120)
        #expect(backgroundRange.minimum == 60)
        #expect(backgroundRange.preferred == 60)
    }

    @MainActor
    @Test("Late artwork preparation preserves a pulse already on screen")
    func lateArtworkPreparationPreservesLiveEffects() async {
        let store = RhythmPulseStore()
        store.registerHit(
            lane: .left,
            emitterOrigin: CGPoint(x: 0.34, y: 0.38)
        )
        let washIDs = store.renderWashes.map(\.id)
        let particleIDs = store.renderParticles.map(\.id)

        await store.prepare(asset: nil)

        #expect(!washIDs.isEmpty)
        #expect(!particleIDs.isEmpty)
        #expect(store.renderWashes.map(\.id) == washIDs)
        #expect(store.renderParticles.map(\.id) == particleIDs)
    }

    @MainActor
    @Test("The rotating background field covers every fullscreen corner")
    func rotatingBackgroundCoversFullscreenCorners() throws {
        let canvas = CGRect(x: 0, y: 0, width: 2560, height: 1400)
        let view = CadenceModeBackgroundView(frame: canvas)
        view.update(
            palette: .fixture,
            appearance: .resolve(
                reduceMotion: false,
                reduceTransparency: false,
                increasedContrast: false
            )
        )
        view.layoutSubtreeIfNeeded()

        let conicLayer = try #require(
            view.layer?.sublayers?
                .compactMap { $0 as? CAGradientLayer }
                .first { $0.type == .conic }
        )
        let minimumScale = 1.02
        let farthestHorizontalEdge = canvas.width * 0.56
        let farthestVerticalEdge = canvas.height * 0.57

        #expect(
            conicLayer.bounds.width * minimumScale / 2
                >= farthestHorizontalEdge + 2
        )
        #expect(
            conicLayer.bounds.height * minimumScale / 2
                >= farthestVerticalEdge + 2
        )
        #expect(conicLayer.shouldRasterize)
        #expect(!conicLayer.drawsAsynchronously)
        let animatedKeyPaths = conicLayer.animationKeys()?.flatMap { key in
            (conicLayer.animation(forKey: key) as? CAAnimationGroup)?
                .animations?
                .compactMap { ($0 as? CAPropertyAnimation)?.keyPath } ?? []
        } ?? []
        #expect(!animatedKeyPaths.contains("transform.rotation.z"))
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
