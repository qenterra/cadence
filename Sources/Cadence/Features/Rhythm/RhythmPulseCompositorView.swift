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

@MainActor
final class RhythmPulseCompositorView: NSView {
    private let effectLayer = CALayer()
    private var state = RhythmPulseCompositorState(
        washes: [],
        particles: [],
        visualQATime: nil,
        panelStartX: 0,
        appearance: nil,
        reduceMotion: false,
        reduceTransparency: false
    )
    private var washLayers: [UInt64: CALayer] = [:]
    private var particleLayers: [UInt64: CALayer] = [:]
    private var washReplacementTimes: [UInt64: TimeInterval] = [:]
    private var washLayerPool: [CALayer] = []
    private var particleLayerPool: [CALayer] = []
    private var previousBounds = CGRect.null
    private let washTextureCache = RhythmPulseWashTextureCache()

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

private extension RhythmPulseCompositorView {
    private func makeWashLayer(_ wash: RhythmPulseWash) -> CALayer {
        let washLayer = washLayerPool.popLast() ?? CALayer()
        RhythmReusableLayer.prepareForReuse(
            washLayer,
            removeFromSuperlayer: false
        )
        washLayer.contents = washTextureCache.image(
            color: wash.color,
            reduceTransparency: state.reduceTransparency
        )
        washLayer.contentsGravity = .resize
        washLayer.minificationFilter = .linear
        washLayer.magnificationFilter = .linear

        let radius = min(bounds.width, bounds.height) * wash.radius
        washLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: radius * 2 * wash.horizontalScale,
            height: radius * 2 * wash.verticalScale
        )

        if let visualQATime = state.visualQATime {
            applyStaticWash(
                wash,
                at: visualQATime,
                to: washLayer
            )
        } else if state.reduceMotion {
            applyStaticWash(
                wash,
                at: ProcessInfo.processInfo.systemUptime,
                to: washLayer
            )
        } else {
            animateWash(wash, layer: washLayer)
        }
        return washLayer
    }

    private func applyStaticWash(
        _ wash: RhythmPulseWash,
        at time: TimeInterval,
        to layer: CALayer
    ) {
        let center = wash.center(at: time)
        layer.position = point(center)
        layer.opacity = Float(wash.opacity(at: time))
        layer.setAffineTransform(
            CGAffineTransform(rotationAngle: wash.rotation)
                .scaledBy(x: wash.scale(at: time), y: wash.scale(at: time))
        )
    }

    private func animateWash(
        _ wash: RhythmPulseWash,
        layer: CALayer
    ) {
        let sampleCount = 5
        let times = normalizedTimes(count: sampleCount)
        let opacitySamples = RhythmPulseCompositorSampling.opacitySamples(
            for: wash
        )
        let group = CAAnimationGroup()
        group.animations = [
            keyframe("position", times: times) { progress in
                NSValue(point: point(wash.center(at: washTime(wash, progress))))
            },
            keyframe(
                "opacity",
                times: opacitySamples.map(\.normalizedTime)
            ) { progress in
                wash.opacity(at: washTime(wash, progress))
            },
            keyframe("transform", times: times) { progress in
                let scale = wash.scale(at: washTime(wash, progress))
                return NSValue(
                    caTransform3D: CATransform3DMakeAffineTransform(
                        CGAffineTransform(rotationAngle: wash.rotation)
                            .scaledBy(x: scale, y: scale)
                    )
                )
            },
        ]
        install(
            group,
            on: layer,
            duration: wash.lifetime,
            startedAt: wash.startedAt,
            key: "wash",
            frameRateRange: washFrameRateRange
        )
    }

    private func makeParticleLayer(_ particle: RhythmParticle) -> CALayer {
        let particleLayer = particleLayerPool.popLast() ?? CALayer()
        RhythmReusableLayer.prepareForReuse(
            particleLayer,
            removeFromSuperlayer: false
        )
        particleLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: particle.size,
            height: particle.size
        )
        particleLayer.cornerRadius = particle.size * 0.5
        particleLayer.backgroundColor = particle.color.cgColor(alpha: 1)

        if let visualQATime = state.visualQATime {
            applyStaticParticle(
                particle,
                at: visualQATime,
                to: particleLayer
            )
        } else {
            animateParticle(particle, layer: particleLayer)
        }
        return particleLayer
    }

    private func recycleWashLayer(_ layer: CALayer) {
        RhythmReusableLayer.prepareForReuse(
            layer,
            removeFromSuperlayer: false
        )
        washLayerPool.append(layer)
    }

    private func updateReplacementFade(
        _ wash: RhythmPulseWash,
        layer: CALayer
    ) {
        guard
            let replacementStartedAt = wash.replacementStartedAt,
            washReplacementTimes[wash.id] != replacementStartedAt
        else {
            return
        }
        washReplacementTimes[wash.id] = replacementStartedAt

        let elapsed = max(
            ProcessInfo.processInfo.systemUptime - replacementStartedAt,
            0
        )
        let duration = max(
            RhythmPulseWash.replacementFadeDuration - elapsed,
            0.001
        )
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = 0
        fade.duration = duration
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        fade.preferredFrameRateRange = washFrameRateRange
        layer.add(fade, forKey: "replacement")
    }

    private func recycleParticleLayer(_ layer: CALayer) {
        RhythmReusableLayer.prepareForReuse(
            layer,
            removeFromSuperlayer: false
        )
        particleLayerPool.append(layer)
    }

    private func reveal(_ layer: CALayer) {
        if layer.superlayer !== effectLayer {
            effectLayer.addSublayer(layer)
        }
        layer.isHidden = false
    }

    private func applyStaticParticle(
        _ particle: RhythmParticle,
        at time: TimeInterval,
        to layer: CALayer
    ) {
        guard let sample = particle.sample(at: time) else {
            layer.opacity = 0
            return
        }
        layer.position = point(sample.position)
        layer.opacity = Float(sample.opacity * intensity(atX: layer.position.x))
        layer.setAffineTransform(particleTransform(sample, baseSize: particle.size))
    }

    private func animateParticle(
        _ particle: RhythmParticle,
        layer: CALayer
    ) {
        let sampleCount = 4
        let times = normalizedTimes(count: sampleCount)
        let samples = times.map { progress in
            particle.sample(at: particle.startedAt + progress * particle.lifetime)
        }
        let group = CAAnimationGroup()
        group.animations = [
            keyframe("position", times: times) { progress in
                let sample = sample(at: progress, in: samples)
                return NSValue(point: point(sample.position))
            },
            keyframe("opacity", times: times) { progress in
                let sample = sample(at: progress, in: samples)
                return sample.opacity * intensity(atX: point(sample.position).x)
            },
            keyframe("transform", times: times) { progress in
                let sample = sample(at: progress, in: samples)
                return NSValue(
                    caTransform3D: CATransform3DMakeAffineTransform(
                        particleTransform(sample, baseSize: particle.size)
                    )
                )
            },
        ]
        install(
            group,
            on: layer,
            duration: particle.lifetime,
            startedAt: particle.startedAt,
            key: "particle",
            frameRateRange: displayFrameRateRange
        )
    }

    private func sample(
        at progress: Double,
        in samples: [RhythmParticleSample?]
    ) -> RhythmParticleSample {
        let index = min(
            Int((progress * Double(samples.count - 1)).rounded()),
            samples.count - 1
        )
        return samples[index] ?? RhythmParticleSample(
            position: .zero,
            size: 0,
            opacity: 0,
            shardAmount: 0,
            rotation: 0
        )
    }

    private func particleTransform(
        _ sample: RhythmParticleSample,
        baseSize: Double
    ) -> CGAffineTransform {
        let scale = sample.size / max(baseSize, 0.01)
        return CGAffineTransform(rotationAngle: sample.rotation)
            .scaledBy(
                x: scale * (1 + sample.shardAmount * 3.2),
                y: scale
            )
    }

    private func install(
        _ animation: CAAnimationGroup,
        on layer: CALayer,
        duration: TimeInterval,
        startedAt: TimeInterval,
        key: String,
        frameRateRange: CAFrameRateRange
    ) {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        animation.duration = duration
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            - elapsed
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = frameRateRange
        layer.add(animation, forKey: key)
    }

    private func keyframe(
        _ keyPath: String,
        times: [Double],
        value: (Double) -> Any
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = times.map(value)
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        return animation
    }

    private func normalizedTimes(count: Int) -> [Double] {
        (0 ..< count).map { Double($0) / Double(count - 1) }
    }

    private func washTime(
        _ wash: RhythmPulseWash,
        _ progress: Double
    ) -> TimeInterval {
        wash.startedAt + progress * wash.lifetime
    }

    private func point(_ normalizedPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: normalizedPoint.x * bounds.width,
            y: normalizedPoint.y * bounds.height
        )
    }

    private func intensity(atX horizontalPosition: Double) -> Double {
        RhythmPulseLayout(
            workspaceWidth: bounds.width,
            panelStartX: state.panelStartX
        ).intensity(atX: horizontalPosition)
    }

    private var displayFrameRateRange: CAFrameRateRange {
        CadenceModePerformancePolicy.animationFrameRateRange(
            displayMaximumFramesPerSecond: window?.screen?
                .maximumFramesPerSecond ?? 60
        )
    }

    private var washFrameRateRange: CAFrameRateRange {
        CadenceModePerformancePolicy.animationFrameRateRange(
            displayMaximumFramesPerSecond: window?.screen?
                .maximumFramesPerSecond ?? 60,
            contentMaximumFramesPerSecond: state.appearance?
                .maximumWashAnimationFramesPerSecond ?? 60
        )
    }
}

private extension RhythmPulseColor {
    func cgColor(alpha: Double) -> CGColor {
        CGColor(
            red: red,
            green: green,
            blue: blue,
            alpha: min(max(alpha, 0), 1)
        )
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
