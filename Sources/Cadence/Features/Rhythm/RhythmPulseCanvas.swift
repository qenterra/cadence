import SwiftUI

struct RhythmPulseCanvas: View {
    @Bindable var store: RhythmPulseStore
    let panelStartX: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            TimelineView(
                .animation(
                    minimumInterval: 1 / 60,
                    paused: !store.hasLiveEffects
                )
            ) { _ in
                let now = store.visualQATime
                    ?? ProcessInfo.processInfo.systemUptime
                let washes = store.renderWashes
                let particles = store.renderParticles
                let layout = RhythmPulseLayout(
                    workspaceWidth: geometry.size.width,
                    panelStartX: panelStartX
                )

                if let palette = store.palette {
                    let appearance = RhythmPulseAppearance.resolve(
                        mode: colorScheme == .dark ? .dark : .light,
                        palette: palette
                    )

                    Canvas(
                        opaque: false,
                        rendersAsynchronously: true
                    ) { context, canvasSize in
                        drawWashes(
                            washes,
                            environment: RhythmWashRenderEnvironment(
                                time: now,
                                canvasSize: canvasSize,
                                layout: layout,
                                appearance: appearance,
                                reduceMotion: reduceMotion,
                                reduceTransparency: reduceTransparency
                            ),
                            context: &context
                        )
                        if !reduceMotion {
                            drawParticles(
                                particles,
                                environment: RhythmWashRenderEnvironment(
                                    time: now,
                                    canvasSize: canvasSize,
                                    layout: layout,
                                    appearance: appearance,
                                    reduceMotion: reduceMotion,
                                    reduceTransparency: reduceTransparency
                                ),
                                context: &context
                            )
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension RhythmPulseCanvas {
    private func drawParticles(
        _ particles: [RhythmParticle],
        environment: RhythmWashRenderEnvironment,
        context: inout GraphicsContext
    ) {
        let geometries = particles.compactMap {
            particleGeometry(for: $0, environment: environment)
        }
        guard !geometries.isEmpty else {
            return
        }

        var particleContext = context
        particleContext.blendMode = .normal
        particleContext.drawLayer { glowLayer in
            glowLayer.addFilter(
                .blur(radius: 3.2, options: .dithersResult)
            )
            drawParticleGeometries(
                geometries,
                opacityMultiplier: 0.72,
                context: &glowLayer
            )
        }
        drawParticleGeometries(
            geometries,
            opacityMultiplier: 1,
            context: &particleContext
        )
    }

    private func particleGeometry(
        for particle: RhythmParticle,
        environment: RhythmWashRenderEnvironment
    ) -> RhythmParticleGeometry? {
        guard let sample = particle.sample(at: environment.time) else {
            return nil
        }
        let center = CGPoint(
            x: sample.position.x * environment.canvasSize.width,
            y: sample.position.y * environment.canvasSize.height
        )
        let opacity = sample.opacity
            * environment.layout.intensity(atX: center.x)
        guard opacity > 0.01 else {
            return nil
        }

        let length = sample.size * (1 + sample.shardAmount * 3.2)
        let thickness = sample.size
            * (0.72 + (1 - sample.shardAmount) * 0.28)
        let path = Path(
            roundedRect: CGRect(
                x: -length * 0.5,
                y: -thickness * 0.5,
                width: length,
                height: thickness
            ),
            cornerRadius: thickness * 0.5
        )
        .applying(CGAffineTransform(rotationAngle: sample.rotation))
        .applying(
            CGAffineTransform(
                translationX: center.x,
                y: center.y
            )
        )
        return RhythmParticleGeometry(
            path: path,
            color: particle.color,
            opacity: opacity
        )
    }

    private func drawParticleGeometries(
        _ geometries: [RhythmParticleGeometry],
        opacityMultiplier: Double,
        context: inout GraphicsContext
    ) {
        for geometry in geometries {
            var coreContext = context
            coreContext.opacity = geometry.opacity * opacityMultiplier
            coreContext.fill(
                geometry.path,
                with: .color(Color(geometry.color))
            )
        }
    }

    private func drawWashes(
        _ washes: [RhythmPulseWash],
        environment: RhythmWashRenderEnvironment,
        context: inout GraphicsContext
    ) {
        var washContext = context
        apply(environment.appearance.washBlendStrategy, to: &washContext)

        if environment.reduceTransparency {
            drawColorFields(
                washes,
                environment: environment,
                colorOpacity: 0.4,
                context: &washContext
            )
            return
        }

        washContext.drawLayer { blurredLayer in
            blurredLayer.addFilter(
                .blur(
                    radius: environment.blurRadius,
                    options: .dithersResult
                )
            )
            drawColorFields(
                washes,
                environment: environment,
                colorOpacity: 0.84,
                context: &blurredLayer
            )
        }
    }

    private func drawColorFields(
        _ washes: [RhythmPulseWash],
        environment: RhythmWashRenderEnvironment,
        colorOpacity: Double,
        context: inout GraphicsContext
    ) {
        for wash in washes where wash.isAlive(at: environment.time) {
            guard let geometry = washGeometry(
                for: wash,
                environment: environment
            ) else {
                continue
            }

            drawWash(
                wash,
                geometry: geometry,
                colorOpacity: colorOpacity,
                context: &context
            )
        }
    }

    private func washGeometry(
        for wash: RhythmPulseWash,
        environment: RhythmWashRenderEnvironment
    ) -> RhythmWashGeometry? {
        let sampledCenter = wash.center(at: environment.time)
        let center = CGPoint(
            x: environment.canvasSize.width * sampledCenter.x,
            y: environment.canvasSize.height * sampledCenter.y
        )
        let scale = environment.reduceMotion
            ? 1
            : wash.scale(at: environment.time)
        let radius = min(
            environment.canvasSize.width,
            environment.canvasSize.height
        ) * wash.radius * scale
        let baseOpacity = environment.reduceMotion
            ? wash.peakOpacity * 0.55
            : wash.opacity(at: environment.time)
        let opacity = baseOpacity
            * environment.layout.intensity(atX: center.x)

        guard opacity > 0.002 else {
            return nil
        }
        return RhythmWashGeometry(
            center: center,
            radius: radius,
            opacity: opacity,
            path: washPath(for: wash, center: center, radius: radius)
        )
    }

    private func drawWash(
        _ wash: RhythmPulseWash,
        geometry: RhythmWashGeometry,
        colorOpacity: Double,
        context: inout GraphicsContext
    ) {
        var washContext = context
        washContext.opacity = geometry.opacity
        washContext.fill(
            geometry.path,
            with: .color(Color(wash.color).opacity(colorOpacity))
        )
    }

    private func washPath(
        for wash: RhythmPulseWash,
        center: CGPoint,
        radius: Double
    ) -> Path {
        Path(
            ellipseIn: CGRect(
                x: -radius * wash.horizontalScale,
                y: -radius * wash.verticalScale,
                width: radius * 2 * wash.horizontalScale,
                height: radius * 2 * wash.verticalScale
            )
        )
        .applying(CGAffineTransform(rotationAngle: wash.rotation))
        .applying(
            CGAffineTransform(translationX: center.x, y: center.y)
        )
    }

    private func apply(
        _ strategy: RhythmPulseBlendStrategy,
        to context: inout GraphicsContext
    ) {
        switch strategy {
        case .multiply:
            context.blendMode = .multiply
        case .screen:
            context.blendMode = .screen
        }
    }
}

private struct RhythmWashRenderEnvironment {
    let time: TimeInterval
    let canvasSize: CGSize
    let layout: RhythmPulseLayout
    let appearance: RhythmPulseAppearance
    let reduceMotion: Bool
    let reduceTransparency: Bool

    var blurRadius: CGFloat {
        min(max(min(canvasSize.width, canvasSize.height) * 0.05, 24), 46)
    }
}

private struct RhythmWashGeometry {
    let center: CGPoint
    let radius: Double
    let opacity: Double
    let path: Path
}

private struct RhythmParticleGeometry {
    let path: Path
    let color: RhythmPulseColor
    let opacity: Double
}

private extension Color {
    init(_ color: RhythmPulseColor) {
        self.init(
            red: color.red,
            green: color.green,
            blue: color.blue
        )
    }
}
