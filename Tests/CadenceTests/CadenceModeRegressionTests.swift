import AppKit
import AVFAudio
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
        #expect(reduced == .identity)
    }

    @Test("Sustained bass drives the meter more than upper mids")
    func bassFilterPrefersLowFrequencies() {
        let sampleRate = 48000.0
        let frameCount = 1024
        var bassFilter = PCMBassEnergyFilter(sampleRate: sampleRate)
        var upperMidFilter = PCMBassEnergyFilter(sampleRate: sampleRate)
        var bassLevel: Float = 0
        var upperMidLevel: Float = 0
        for chunk in 0 ..< 32 {
            let bass = (0 ..< frameCount).map { frame in
                let sample = chunk * frameCount + frame
                return Float(
                    sin(2 * Double.pi * 80 * Double(sample) / sampleRate)
                        * 0.35
                )
            }
            let upperMid = (0 ..< frameCount).map { frame in
                let sample = chunk * frameCount + frame
                return Float(
                    sin(2 * Double.pi * 1200 * Double(sample) / sampleRate)
                        * 0.35
                )
            }
            bassLevel = bassFilter.process(samples: bass)
            upperMidLevel = upperMidFilter.process(samples: upperMid)
        }

        #expect(bassLevel > 0.2)
        #expect(bassLevel > upperMidLevel * 2)
        #expect((0 ... 1).contains(bassLevel))
    }

    @Test("PCM bass tap processes audio away from the main actor")
    func bassTapIsRealtimeSafe() async throws {
        let meter = PCMBassLevelMeter()
        let analyzer = PCMBassAnalyzer(meter: meter)
        let tap = makePCMBassTap(analyzer: analyzer)

        try await Task.detached {
            let format = try #require(
                AVAudioFormat(
                    standardFormatWithSampleRate: 48000,
                    channels: 1
                )
            )
            let buffer = try #require(
                AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)
            )
            buffer.frameLength = buffer.frameCapacity
            let samples = try #require(buffer.floatChannelData?[0])
            for frame in 0 ..< Int(buffer.frameLength) {
                samples[frame] = Float(
                    sin(2 * Double.pi * 80 * Double(frame) / 48000) * 0.35
                )
            }
            tap(buffer, AVAudioTime(sampleTime: 0, atRate: 48000))
        }.value

        #expect(meter.currentBassLevel() > 0)
    }

    @MainActor
    @Test("Bass artwork rises quickly and releases across display frames")
    func bassArtworkResponseIsSmoothed() {
        let smoother = CadenceModeBassSmoother()

        let first = smoother.resolve(target: 1, timestamp: 0)
        let second = smoother.resolve(target: 1, timestamp: 1.0 / 120.0)
        let third = smoother.resolve(target: 1, timestamp: 2.0 / 120.0)
        let release = smoother.resolve(target: 0, timestamp: 3.0 / 120.0)

        #expect(first > 0.5)
        #expect(first < second)
        #expect(second < third)
        #expect(third < 1)
        #expect(release < third)
        #expect(release > third * 0.85)
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
