import CoreGraphics
import Foundation

struct RhythmParticleSample: Equatable, Sendable {
    let position: CGPoint
    let size: Double
    let opacity: Double
    let shardAmount: Double
    let rotation: Double
}

struct RhythmParticle: Identifiable, Sendable {
    let id: UInt64
    let lane: RhythmLane
    let color: RhythmPulseColor
    let origin: CGPoint
    let emissionOffset: CGVector
    let velocity: CGVector
    let gravity: Double
    let drag: Double
    let size: Double
    let spin: Double
    let startedAt: TimeInterval
    let lifetime: TimeInterval
    let peakOpacity: Double
    let travelOpacity: Double

    func sample(at time: TimeInterval) -> RhythmParticleSample? {
        guard time >= startedAt, time < startedAt + lifetime else {
            return nil
        }
        let elapsed = time - startedAt
        let progress = elapsed / lifetime
        let damping = exp(-drag * elapsed)
        let travel = (1 - damping) / drag
        let horizontalVelocity = velocity.dx * damping
        let verticalVelocity = velocity.dy * damping + gravity * elapsed
        let opacity = particleOpacity(at: progress)

        return RhythmParticleSample(
            position: CGPoint(
                x: origin.x + emissionOffset.dx + velocity.dx * travel,
                y: origin.y + emissionOffset.dy + velocity.dy * travel
                    + gravity * elapsed * elapsed * 0.5
            ),
            size: size * (1 - smootherParticleStep(progress) * 0.55),
            opacity: opacity,
            shardAmount: 1 - smoothParticleStep(progress / 0.58),
            rotation: atan2(verticalVelocity, horizontalVelocity)
                + spin * elapsed
        )
    }

    func isExpired(at time: TimeInterval) -> Bool {
        time >= startedAt + lifetime
    }

    private func particleOpacity(at progress: Double) -> Double {
        if progress <= 0.1 {
            return peakOpacity * smoothParticleStep(progress / 0.1)
        }
        if progress <= 0.68 {
            let travelProgress = (progress - 0.1) / 0.58
            return peakOpacity
                + (travelOpacity - peakOpacity) * travelProgress
        }
        return travelOpacity
            * (1 - smootherParticleStep((progress - 0.68) / 0.32))
    }
}

struct RhythmParticleSimulation: Sendable {
    static let maximumParticleCount = 32
    static let maximumLifecycleDuration: TimeInterval = 1.67

    private(set) var allParticles: [RhythmParticle] = []

    mutating func registerHit(
        lane: RhythmLane,
        origin: CGPoint,
        palette: RhythmAccentPalette,
        time: TimeInterval,
        generator: inout some RandomNumberGenerator
    ) {
        guard !palette.colors.isEmpty else {
            return
        }

        removeExpired(at: time)
        let count = 7 + Int(generator.next() % 3)
        allParticles.append(contentsOf: (0 ..< count).map { _ in
            makeParticle(
                lane: lane,
                origin: origin,
                palette: palette,
                time: time,
                generator: &generator
            )
        })
        let overflow = allParticles.count - Self.maximumParticleCount
        if overflow > 0 {
            allParticles.removeFirst(overflow)
        }
    }

    mutating func removeExpired(at time: TimeInterval) {
        allParticles.removeAll { $0.isExpired(at: time) }
    }

    mutating func removeAll() {
        allParticles.removeAll(keepingCapacity: true)
    }

    private func makeParticle(
        lane: RhythmLane,
        origin: CGPoint,
        palette: RhythmAccentPalette,
        time: TimeInterval,
        generator: inout some RandomNumberGenerator
    ) -> RhythmParticle {
        let spread = particleRandom(in: 0.55 ... 2.05, using: &generator)
        let baseAngle = lane == .left ? Double.pi : 0
        let angle = baseAngle
            + particleRandom(in: -0.5 ... 0.5, using: &generator) * spread
        let speed = particleRandom(in: 0.18 ... 0.62, using: &generator)
        let lifetime = particleRandom(in: 0.7 ... 1.55, using: &generator)

        return RhythmParticle(
            id: generator.next(),
            lane: lane,
            color: particleRandomElement(
                in: palette.colors,
                using: &generator
            ),
            origin: origin,
            emissionOffset: CGVector(
                dx: particleRandom(in: -0.02 ... 0.02, using: &generator),
                dy: particleRandom(in: -0.025 ... 0.025, using: &generator)
            ),
            velocity: CGVector(
                dx: cos(angle) * speed,
                dy: sin(angle) * speed
            ),
            gravity: particleRandom(in: 0.18 ... 0.5, using: &generator),
            drag: particleRandom(in: 0.35 ... 1.1, using: &generator),
            size: particleRandom(in: 1.8 ... 4.8, using: &generator),
            spin: particleRandom(in: -8 ... 8, using: &generator),
            startedAt: time
                + particleRandom(in: 0 ... 0.12, using: &generator),
            lifetime: lifetime,
            peakOpacity: particleRandom(in: 0.68 ... 1, using: &generator),
            travelOpacity: particleRandom(in: 0.28 ... 0.72, using: &generator)
        )
    }
}

private func smoothParticleStep(_ progress: Double) -> Double {
    let value = min(max(progress, 0), 1)
    return value * value * (3 - 2 * value)
}

private func smootherParticleStep(_ progress: Double) -> Double {
    let value = min(max(progress, 0), 1)
    return value * value * value
        * (value * (value * 6 - 15) + 10)
}

private func particleRandom(
    in range: ClosedRange<Double>,
    using generator: inout some RandomNumberGenerator
) -> Double {
    let unit = Double(generator.next()) / Double(UInt64.max)
    return range.lowerBound + unit * (range.upperBound - range.lowerBound)
}

private func particleRandomElement<Element>(
    in elements: [Element],
    using generator: inout some RandomNumberGenerator
) -> Element {
    let index = Int(generator.next() % UInt64(elements.count))
    return elements[index]
}
