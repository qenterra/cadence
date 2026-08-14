import Observation
import SwiftUI

/// Main-actor owner of Cadence Mode's deterministic simulations and compositor.
/// Palette extraction may suspend offscreen, so its asset key is rechecked
/// before publication to prevent an older artwork task replacing newer state.
@MainActor
@Observable
final class RhythmPulseStore {
    private(set) var palette: RhythmAccentPalette? = .cadenceFallback
    private(set) var hasLiveEffects = false
    private(set) var visualQATime: TimeInterval?
    @ObservationIgnored private var simulation = RhythmPulseSimulation()
    @ObservationIgnored private var particleSimulation = RhythmParticleSimulation()

    @ObservationIgnored private let paletteCache = RhythmArtworkPaletteCache()
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var preparedAssetKey: String?
    @ObservationIgnored private weak var compositorView:
        RhythmPulseCompositorView?

    func attachCompositor(_ view: RhythmPulseCompositorView) {
        compositorView = view
    }

    func prepare(asset: ArtworkAsset?) async {
        let assetKey = asset.map {
            "\($0.id.uuidString)-\($0.revision)-\($0.variant)"
        } ?? "missing-artwork"
        guard assetKey != preparedAssetKey else {
            return
        }

        preparedAssetKey = assetKey
        guard let asset else {
            palette = .cadenceFallback
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
        let effectPalette = palette.effectPalette

        let now = ProcessInfo.processInfo.systemUptime
        simulation.registerHit(
            lane: lane,
            origin: emitterOrigin,
            palette: effectPalette,
            time: now,
            generator: &generator
        )
        particleSimulation.registerHit(
            lane: lane,
            origin: emitterOrigin,
            palette: effectPalette,
            time: now,
            generator: &generator
        )
        hasLiveEffects = true
        publishEffects()
        scheduleCleanup()
    }

    func prepare(visualQAState: RhythmPulseVisualQAState) {
        let laneKey = visualQAState.lanes.map {
            $0 == .left ? "left" : "right"
        }.joined(separator: "-")
        let stateKey = [
            "visual-qa",
            String(visualQAState.seed),
            String(visualQAState.isCadenceModeActive == true),
            laneKey,
        ].joined(separator: "-")
        guard preparedAssetKey != stateKey else {
            return
        }

        reset()
        preparedAssetKey = stateKey
        palette = visualQAState.palette
        let effectPalette = visualQAState.palette.effectPalette
        var random = SplitMix64(seed: visualQAState.seed)
        let snapshotTime = ProcessInfo.processInfo.systemUptime
        for lane in visualQAState.lanes {
            let emitterOrigin = if visualQAState.isCadenceModeActive == true {
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
                palette: effectPalette,
                time: snapshotTime - 0.14,
                generator: &random
            )
            particleSimulation.registerHit(
                lane: lane,
                origin: emitterOrigin,
                palette: effectPalette,
                time: snapshotTime - 0.14,
                generator: &random
            )
        }
        visualQATime = snapshotTime
        hasLiveEffects = false
        publishEffects()
    }

    var renderWashes: [RhythmPulseWash] {
        simulation.allWashes
    }

    var renderParticles: [RhythmParticle] {
        particleSimulation.allParticles
    }

    var hasAttachedCompositor: Bool {
        compositorView != nil
    }

    var visibleCompositorEffectCount: Int {
        compositorView?.visibleEffectCount ?? 0
    }

    func reset() {
        cleanupTask?.cancel()
        cleanupTask = nil
        simulation.removeAll()
        particleSimulation.removeAll()
        hasLiveEffects = false
        visualQATime = nil
        publishEffects()
    }

    private func scheduleCleanup() {
        // One cleanup task represents the latest hit deadline. Replacing it is
        // required: independent timers could clear effects created by a newer hit.
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
            publishEffects()
        }
    }

    private func publishEffects() {
        compositorView?.updateEffects(
            washes: simulation.allWashes,
            particles: particleSimulation.allParticles,
            visualQATime: visualQATime
        )
    }
}

struct RhythmPulseVisualQAState: Sendable {
    let palette: RhythmAccentPalette
    let seed: UInt64
    let lanes: [RhythmLane]
    let isCadenceModeActive: Bool?
    let cadenceModeLyricDocument: LyricDocument?
    let cadenceModePresentationTime: TimeInterval?

    init(
        palette: RhythmAccentPalette,
        seed: UInt64,
        lanes: [RhythmLane],
        isCadenceModeActive: Bool? = nil,
        cadenceModeLyricDocument: LyricDocument? = nil,
        cadenceModePresentationTime: TimeInterval? = nil
    ) {
        self.palette = palette
        self.seed = seed
        self.lanes = lanes
        self.isCadenceModeActive = isCadenceModeActive
        self.cadenceModeLyricDocument = cadenceModeLyricDocument
        self.cadenceModePresentationTime = cadenceModePresentationTime
    }
}

extension EnvironmentValues {
    @Entry var rhythmPulseVisualQAState: RhythmPulseVisualQAState?
}
