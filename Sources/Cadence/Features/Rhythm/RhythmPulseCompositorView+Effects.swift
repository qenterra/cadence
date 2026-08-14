import AppKit
import QuartzCore

private struct RhythmAnimationTiming {
    let duration: TimeInterval
    let startedAt: TimeInterval
    let key: String
    let frameRateRange: CAFrameRateRange
}

extension RhythmPulseCompositorView {
    func makeWashLayer(_ wash: RhythmPulseWash) -> CALayer {
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

    func applyStaticWash(
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

    func animateWash(
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
            timing: RhythmAnimationTiming(
                duration: wash.lifetime,
                startedAt: wash.startedAt,
                key: "wash",
                frameRateRange: washFrameRateRange
            )
        )
    }

    func makeParticleLayer(_ particle: RhythmParticle) -> CALayer {
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

    func recycleWashLayer(_ layer: CALayer) {
        RhythmReusableLayer.prepareForReuse(
            layer,
            removeFromSuperlayer: false
        )
        washLayerPool.append(layer)
    }

    func updateReplacementFade(
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

    func recycleParticleLayer(_ layer: CALayer) {
        RhythmReusableLayer.prepareForReuse(
            layer,
            removeFromSuperlayer: false
        )
        particleLayerPool.append(layer)
    }

    func reveal(_ layer: CALayer) {
        if layer.superlayer !== effectLayer {
            effectLayer.addSublayer(layer)
        }
        layer.isHidden = false
    }

    func applyStaticParticle(
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

    func animateParticle(
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
            timing: RhythmAnimationTiming(
                duration: particle.lifetime,
                startedAt: particle.startedAt,
                key: "particle",
                frameRateRange: displayFrameRateRange
            )
        )
    }

    func sample(
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

    func particleTransform(
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
        timing: RhythmAnimationTiming
    ) {
        let elapsed = ProcessInfo.processInfo.systemUptime - timing.startedAt
        animation.duration = timing.duration
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            - elapsed
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = timing.frameRateRange
        layer.add(animation, forKey: timing.key)
    }

    func keyframe(
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

    func normalizedTimes(count: Int) -> [Double] {
        (0 ..< count).map { Double($0) / Double(count - 1) }
    }

    func washTime(
        _ wash: RhythmPulseWash,
        _ progress: Double
    ) -> TimeInterval {
        wash.startedAt + progress * wash.lifetime
    }

    func point(_ normalizedPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: normalizedPoint.x * bounds.width,
            y: normalizedPoint.y * bounds.height
        )
    }

    func intensity(atX horizontalPosition: Double) -> Double {
        RhythmPulseLayout(
            workspaceWidth: bounds.width,
            panelStartX: state.panelStartX
        ).intensity(atX: horizontalPosition)
    }

    var displayFrameRateRange: CAFrameRateRange {
        CadenceModePerformancePolicy.animationFrameRateRange(
            displayMaximumFramesPerSecond: window?.screen?
                .maximumFramesPerSecond ?? 60
        )
    }

    var washFrameRateRange: CAFrameRateRange {
        CadenceModePerformancePolicy.animationFrameRateRange(
            displayMaximumFramesPerSecond: window?.screen?
                .maximumFramesPerSecond ?? 60,
            contentMaximumFramesPerSecond: state.appearance?
                .maximumWashAnimationFramesPerSecond ?? 60
        )
    }
}
