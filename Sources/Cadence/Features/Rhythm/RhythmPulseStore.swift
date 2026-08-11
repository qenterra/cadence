import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class RhythmPulseStore {
    private(set) var palette: RhythmAccentPalette?
    private(set) var hasLiveEffects = false
    private(set) var visualQATime: TimeInterval?
    private var simulation = RhythmPulseSimulation()
    private var particleSimulation = RhythmParticleSimulation()

    @ObservationIgnored private let paletteCache = RhythmArtworkPaletteCache()
    @ObservationIgnored private let haptics = RhythmHapticPerformer()
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var preparedAssetKey: String?

    func prepare(asset: ArtworkAsset?) async {
        let assetKey = asset.map {
            "\($0.id.uuidString)-\($0.revision)-\($0.variant)"
        }
        guard assetKey != preparedAssetKey else {
            return
        }

        reset()
        preparedAssetKey = assetKey
        guard let asset else {
            palette = nil
            return
        }

        let extractedPalette = await paletteCache.palette(for: asset)
        guard !Task.isCancelled, preparedAssetKey == assetKey else {
            return
        }
        palette = extractedPalette
    }

    func registerHit(
        lane: RhythmLane,
        emitterOrigin: CGPoint = .zero
    ) {
        guard let palette else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        simulation.registerHit(
            lane: lane,
            origin: emitterOrigin,
            palette: palette,
            time: now,
            generator: &generator
        )
        particleSimulation.registerHit(
            lane: lane,
            origin: emitterOrigin,
            palette: palette,
            time: now,
            generator: &generator
        )
        hasLiveEffects = true
        haptics.perform()
        scheduleCleanup()
    }

    func prepare(visualQAState: RhythmPulseVisualQAState) {
        let laneKey = visualQAState.lanes.map {
            $0 == .left ? "left" : "right"
        }.joined(separator: "-")
        let stateKey = [
            "visual-qa",
            String(visualQAState.seed),
            String(visualQAState.isFocusActive == true),
            laneKey,
        ].joined(separator: "-")
        guard preparedAssetKey != stateKey else {
            return
        }

        reset()
        preparedAssetKey = stateKey
        palette = visualQAState.palette
        var random = SplitMix64(seed: visualQAState.seed)
        let snapshotTime = ProcessInfo.processInfo.systemUptime
        for lane in visualQAState.lanes {
            let emitterOrigin = if visualQAState.isFocusActive == true {
                CGPoint(
                    x: lane == .left ? 0.34 : 0.66,
                    y: 0.38
                )
            } else {
                CGPoint(
                    x: lane == .left ? 0.04 : 0.4,
                    y: 0.36
                )
            }
            simulation.registerHit(
                lane: lane,
                origin: emitterOrigin,
                palette: visualQAState.palette,
                time: snapshotTime - 0.14,
                generator: &random
            )
            particleSimulation.registerHit(
                lane: lane,
                origin: emitterOrigin,
                palette: visualQAState.palette,
                time: snapshotTime - 0.14,
                generator: &random
            )
        }
        visualQATime = snapshotTime
        hasLiveEffects = false
    }

    var renderWashes: [RhythmPulseWash] {
        simulation.allWashes
    }

    var renderParticles: [RhythmParticle] {
        particleSimulation.allParticles
    }

    func reset() {
        cleanupTask?.cancel()
        cleanupTask = nil
        simulation.removeAll()
        particleSimulation.removeAll()
        hasLiveEffects = false
        visualQATime = nil
    }

    private func scheduleCleanup() {
        cleanupTask?.cancel()
        cleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: .seconds(
                    max(
                        RhythmPulseWash.fluidLifetime,
                        RhythmParticleSimulation.maximumLifecycleDuration
                    ) + 0.1
                )
            )
            guard let self, !Task.isCancelled else {
                return
            }
            simulation.removeExpired(
                at: ProcessInfo.processInfo.systemUptime
            )
            particleSimulation.removeExpired(
                at: ProcessInfo.processInfo.systemUptime
            )
            hasLiveEffects = false
        }
    }
}

struct RhythmPulseVisualQAState: Sendable {
    let palette: RhythmAccentPalette
    let seed: UInt64
    let lanes: [RhythmLane]
    let isFocusActive: Bool?
    let focusLyricDocument: LyricDocument?
    let focusPresentationTime: TimeInterval?

    init(
        palette: RhythmAccentPalette,
        seed: UInt64,
        lanes: [RhythmLane],
        isFocusActive: Bool? = nil,
        focusLyricDocument: LyricDocument? = nil,
        focusPresentationTime: TimeInterval? = nil
    ) {
        self.palette = palette
        self.seed = seed
        self.lanes = lanes
        self.isFocusActive = isFocusActive
        self.focusLyricDocument = focusLyricDocument
        self.focusPresentationTime = focusPresentationTime
    }
}

extension EnvironmentValues {
    @Entry var rhythmPulseVisualQAState: RhythmPulseVisualQAState?
}

@MainActor
private final class RhythmHapticPerformer {
    private var lastPerformanceTime: TimeInterval = 0

    func perform() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPerformanceTime >= 0.12 else {
            return
        }
        lastPerformanceTime = now
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }
}
