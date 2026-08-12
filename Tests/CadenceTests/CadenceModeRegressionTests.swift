import AppKit
@testable import Cadence
import QuartzCore
import Testing

struct CadenceModeRegressionTests {
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
