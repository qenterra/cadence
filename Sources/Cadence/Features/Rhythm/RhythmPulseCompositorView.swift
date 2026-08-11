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

    private func configureLayerTree() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(effectLayer)
        layerContentsRedrawPolicy = .never
        washLayerPool = (0 ..< 12).map { _ in CALayer() }
        particleLayerPool = (0 ..< 16).map { _ in CALayer() }
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
                effectLayer.addSublayer(washLayer)
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
            effectLayer.addSublayer(particleLayer)
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
        washLayer.removeAllAnimations()
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
        washLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

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
        let group = CAAnimationGroup()
        group.animations = [
            keyframe("position", times: times) { progress in
                NSValue(point: point(wash.center(at: washTime(wash, progress))))
            },
            keyframe("opacity", times: times) { progress in
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
            key: "wash"
        )
    }

    private func makeParticleLayer(_ particle: RhythmParticle) -> CALayer {
        let particleLayer = particleLayerPool.popLast() ?? CALayer()
        particleLayer.removeAllAnimations()
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
        layer.removeAllAnimations()
        layer.removeFromSuperlayer()
        layer.contents = nil
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
        fade.preferredFrameRateRange = preferredFrameRateRange
        layer.add(fade, forKey: "replacement")
    }

    private func recycleParticleLayer(_ layer: CALayer) {
        layer.removeAllAnimations()
        layer.removeFromSuperlayer()
        particleLayerPool.append(layer)
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
            key: "particle"
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
        key: String
    ) {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        animation.duration = duration
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            - elapsed
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = preferredFrameRateRange
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

    private var preferredFrameRateRange: CAFrameRateRange {
        let maximumFramesPerSecond = Float(
            window?.screen?.maximumFramesPerSecond ?? 60
        )
        return CAFrameRateRange(
            minimum: min(60, maximumFramesPerSecond),
            maximum: maximumFramesPerSecond,
            preferred: maximumFramesPerSecond
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
