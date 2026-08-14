import AppKit
import QuartzCore

struct RhythmPulseCompositorState {
    var washes: [RhythmPulseWash]
    var particles: [RhythmParticle]
    var visualQATime: TimeInterval?
    let panelStartX: CGFloat
    let appearance: RhythmPulseAppearance?
    let reduceMotion: Bool
    let reduceTransparency: Bool
}

struct RhythmPulseOpacitySample: Equatable, Sendable {
    let time: TimeInterval
    let normalizedTime: Double
    let opacity: Double
}

enum RhythmPulseCompositorSampling {
    static func opacitySamples(
        for wash: RhythmPulseWash
    ) -> [RhythmPulseOpacitySample] {
        let sampleTimes = [
            0,
            min(0.02, wash.lifetime),
            min(0.11, wash.lifetime),
            wash.lifetime * 0.3,
            wash.lifetime * 0.6,
            wash.lifetime,
        ]
        return sampleTimes.map { elapsed in
            RhythmPulseOpacitySample(
                time: wash.startedAt + elapsed,
                normalizedTime: elapsed / wash.lifetime,
                opacity: wash.opacity(at: wash.startedAt + elapsed)
            )
        }
    }
}

@MainActor
enum RhythmReusableLayer {
    static func prepareForReuse(
        _ layer: CALayer,
        removeFromSuperlayer: Bool = true
    ) {
        layer.isHidden = true
        layer.removeAllAnimations()
        if removeFromSuperlayer {
            layer.removeFromSuperlayer()
        }
        layer.contents = nil
        layer.backgroundColor = nil
        layer.bounds = .zero
        layer.position = .zero
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.opacity = 0
        layer.cornerRadius = 0
        layer.transform = CATransform3DIdentity
    }
}

/// AppKit/Core Animation renderer for published rhythm snapshots.
///
/// All layer-tree mutation stays on the main actor and inside disabled implicit
/// transactions; the display server owns interpolation after layers are updated.
@MainActor
final class RhythmPulseCompositorView: NSView {
    let effectLayer = CALayer()
    var state = RhythmPulseCompositorState(
        washes: [],
        particles: [],
        visualQATime: nil,
        panelStartX: 0,
        appearance: nil,
        reduceMotion: false,
        reduceTransparency: false
    )
    var washLayers: [UInt64: CALayer] = [:]
    var particleLayers: [UInt64: CALayer] = [:]
    var washReplacementTimes: [UInt64: TimeInterval] = [:]
    var washLayerPool: [CALayer] = []
    var particleLayerPool: [CALayer] = []
    private var previousBounds = CGRect.null
    let washTextureCache = RhythmPulseWashTextureCache()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayerTree()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayerTree()
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        guard bounds != previousBounds else {
            return
        }
        previousBounds = bounds
        CATransaction.performWithoutAnimation {
            effectLayer.frame = bounds
        }
        rebuildLayers()
    }

    func update(_ state: RhythmPulseCompositorState) {
        self.state = state
        prepareWashTextures()
        reconcileLayers()
    }

    func updateEffects(
        washes: [RhythmPulseWash],
        particles: [RhythmParticle],
        visualQATime: TimeInterval?
    ) {
        state.washes = washes
        state.particles = particles
        state.visualQATime = visualQATime
        reconcileLayers()
    }

    var visibleEffectCount: Int {
        washLayers.values.count(where: isVisibleEffectLayer)
            + particleLayers.values.count(where: isVisibleEffectLayer)
    }

    private func isVisibleEffectLayer(_ layer: CALayer) -> Bool {
        guard !layer.isHidden else {
            return false
        }
        return (layer.presentation()?.opacity ?? layer.opacity) > 0.001
    }

    private func configureLayerTree() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(effectLayer)
        layerContentsRedrawPolicy = .never
        washLayerPool = makeAttachedLayerPool(count: 12)
        particleLayerPool = makeAttachedLayerPool(
            count: RhythmParticleSimulation.maximumParticleCount
        )
    }

    private func makeAttachedLayerPool(count: Int) -> [CALayer] {
        (0 ..< count).map { _ in
            let layer = CALayer()
            RhythmReusableLayer.prepareForReuse(
                layer,
                removeFromSuperlayer: false
            )
            effectLayer.addSublayer(layer)
            return layer
        }
    }

    private func rebuildLayers() {
        washLayers.values.forEach(recycleWashLayer)
        particleLayers.values.forEach(recycleParticleLayer)
        washLayers.removeAll(keepingCapacity: true)
        particleLayers.removeAll(keepingCapacity: true)
        washReplacementTimes.removeAll(keepingCapacity: true)
        reconcileLayers()
    }

    private func reconcileLayers() {
        guard !bounds.isEmpty, state.appearance != nil else {
            return
        }
        CATransaction.performWithoutAnimation {
            reconcileLayersWithoutImplicitAnimations()
        }
    }

    private func reconcileLayersWithoutImplicitAnimations() {
        removeMissingLayers(
            keepingWashIDs: Set(state.washes.map(\.id)),
            keepingParticleIDs: Set(state.particles.map(\.id))
        )

        for wash in state.washes {
            if let washLayer = washLayers[wash.id] {
                updateReplacementFade(wash, layer: washLayer)
            } else {
                let washLayer = makeWashLayer(wash)
                washLayers[wash.id] = washLayer
                reveal(washLayer)
                updateReplacementFade(wash, layer: washLayer)
            }
        }
        guard !state.reduceMotion else {
            return
        }
        for particle in state.particles
            where particleLayers[particle.id] == nil {
            let particleLayer = makeParticleLayer(
                particle
            )
            particleLayers[particle.id] = particleLayer
            reveal(particleLayer)
        }
    }

    private func prepareWashTextures() {
        guard let appearance = state.appearance else {
            return
        }
        washTextureCache.prepare(
            colors: appearance.colors,
            reduceTransparency: state.reduceTransparency
        )
    }

    private func removeMissingLayers(
        keepingWashIDs: Set<UInt64>,
        keepingParticleIDs: Set<UInt64>
    ) {
        let removedWashIDs = washLayers.keys.filter {
            !keepingWashIDs.contains($0)
        }
        for id in removedWashIDs {
            guard let layer = washLayers.removeValue(forKey: id) else {
                continue
            }
            washReplacementTimes.removeValue(forKey: id)
            recycleWashLayer(layer)
        }
        let removedParticleIDs = particleLayers.keys.filter {
            !keepingParticleIDs.contains($0)
        }
        for id in removedParticleIDs {
            guard let layer = particleLayers.removeValue(forKey: id) else {
                continue
            }
            recycleParticleLayer(layer)
        }
        if state.reduceMotion {
            particleLayers.values.forEach(recycleParticleLayer)
            particleLayers.removeAll(keepingCapacity: true)
        }
    }
}

private extension CATransaction {
    static func performWithoutAnimation(_ updates: () -> Void) {
        begin()
        setDisableActions(true)
        updates()
        commit()
    }
}
