import CoreGraphics
import Foundation

enum RhythmLane: Hashable, Sendable {
    case left
    case right
}

struct RhythmPulseColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    var saturation: Double {
        let highest = max(red, green, blue)
        guard highest > 0 else {
            return 0
        }
        return (highest - min(red, green, blue)) / highest
    }

    func isNear(
        red targetRed: Double,
        green targetGreen: Double,
        blue targetBlue: Double,
        tolerance: Double = 0.08
    ) -> Bool {
        abs(red - targetRed) <= tolerance
            && abs(green - targetGreen) <= tolerance
            && abs(blue - targetBlue) <= tolerance
    }
}

struct RhythmAccentPalette: Hashable, Sendable {
    let colors: [RhythmPulseColor]

    init(colors: [RhythmPulseColor]) {
        self.colors = Array(colors.prefix(5))
    }
}

struct RhythmPulseWash: Identifiable, Hashable, Sendable {
    static let fluidLifetime: TimeInterval = 1.1
    static let replacementFadeDuration: TimeInterval = 0.08

    let id: UInt64
    let lane: RhythmLane
    let color: RhythmPulseColor
    let origin: CGPoint
    let destination: CGPoint
    let radius: Double
    let horizontalScale: Double
    let verticalScale: Double
    let rotation: Double
    let startedAt: TimeInterval
    let lifetime: TimeInterval
    let peakOpacity: Double
    private(set) var replacementStartedAt: TimeInterval?

    var isBeingReplaced: Bool {
        replacementStartedAt != nil
    }

    func opacity(at time: TimeInterval) -> Double {
        let progress = impactProgress(at: time)
        let naturalOpacity: Double = if progress <= 0.1 {
            peakOpacity * progress / 0.1
        } else {
            peakOpacity
                * (1 - (progress - 0.1) / 0.9)
        }
        guard let replacementStartedAt else {
            return naturalOpacity
        }
        let replacementProgress = (time - replacementStartedAt)
            / Self.replacementFadeDuration
        return naturalOpacity * (1 - smootherStep(replacementProgress))
    }

    func scale(at time: TimeInterval) -> Double {
        0.2 + impactProgress(at: time) * 1.28
    }

    func center(at time: TimeInterval) -> CGPoint {
        let progress = impactProgress(at: time)
        return CGPoint(
            x: origin.x + (destination.x - origin.x) * progress,
            y: origin.y + (destination.y - origin.y) * progress
        )
    }

    func isAlive(at time: TimeInterval) -> Bool {
        let withinNaturalLifetime = time >= startedAt
            && time < startedAt + lifetime
        guard let replacementStartedAt else {
            return withinNaturalLifetime
        }
        return withinNaturalLifetime
            && time < replacementStartedAt + Self.replacementFadeDuration
    }

    mutating func beginReplacement(at time: TimeInterval) {
        replacementStartedAt = time
    }

    private func elapsedTime(at time: TimeInterval) -> Double {
        min(max(time - startedAt, 0), lifetime)
    }

    private func impactProgress(at time: TimeInterval) -> Double {
        rhythmImpactEase(elapsedTime(at: time) / lifetime)
    }
}

struct RhythmPulseSimulation: Sendable {
    private(set) var allWashes: [RhythmPulseWash] = []

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
        allWashes.removeAll {
            $0.lane == lane && $0.isBeingReplaced
        }
        for index in allWashes.indices where allWashes[index].lane == lane {
            allWashes[index].beginReplacement(at: time)
        }
        let spawnContext = RhythmWashSpawnContext(
            lane: lane,
            origin: origin,
            palette: palette,
            time: time
        )
        allWashes.append(contentsOf: (0 ..< 3).map { index in
            makeWash(
                index: index,
                spawnContext: spawnContext,
                generator: &generator
            )
        })
    }

    mutating func removeExpired(at time: TimeInterval) {
        allWashes.removeAll { !$0.isAlive(at: time) }
    }

    mutating func removeAll() {
        allWashes.removeAll(keepingCapacity: true)
    }

    func washes(at time: TimeInterval) -> [RhythmPulseWash] {
        allWashes.filter { $0.isAlive(at: time) }
    }

    private func makeWash(
        index: Int,
        spawnContext: RhythmWashSpawnContext,
        generator: inout some RandomNumberGenerator
    ) -> RhythmPulseWash {
        let horizontalDirection = spawnContext.lane == .left ? -1.0 : 1.0
        let horizontalTravel = random(
            in: 0.1 ... 0.42,
            using: &generator
        )
        let verticalTravel = random(
            in: -0.35 ... 0.35,
            using: &generator
        )
        let destination = CGPoint(
            x: min(
                max(
                    spawnContext.origin.x
                        + horizontalDirection * horizontalTravel,
                    0.02
                ),
                0.98
            ),
            y: min(
                max(spawnContext.origin.y + verticalTravel, 0.06),
                0.94
            )
        )

        return RhythmPulseWash(
            id: randomID(using: &generator) ^ UInt64(index),
            lane: spawnContext.lane,
            color: randomElement(
                in: spawnContext.palette.colors,
                using: &generator
            ),
            origin: spawnContext.origin,
            destination: destination,
            radius: random(in: 0.12 ... 0.28, using: &generator),
            horizontalScale: random(in: 0.82 ... 1.34, using: &generator),
            verticalScale: random(in: 0.7 ... 1.18, using: &generator),
            rotation: random(in: -0.22 ... 0.22, using: &generator),
            startedAt: spawnContext.time,
            lifetime: RhythmPulseWash.fluidLifetime,
            peakOpacity: random(in: 0.48 ... 0.91, using: &generator),
            replacementStartedAt: nil
        )
    }
}

private struct RhythmWashSpawnContext {
    let lane: RhythmLane
    let origin: CGPoint
    let palette: RhythmAccentPalette
    let time: TimeInterval
}

struct RhythmPulseLayout: Sendable {
    let workspaceWidth: Double
    let panelStartX: Double

    var clipRect: CGRect {
        CGRect(x: 0, y: 0, width: workspaceWidth, height: 1)
    }

    func intensity(atX horizontalPosition: Double) -> Double {
        guard workspaceWidth > 0 else {
            return 0
        }
        let transitionStart = panelStartX - 90
        let transitionEnd = panelStartX + 360
        let progress = min(
            max(
                (horizontalPosition - transitionStart)
                    / (transitionEnd - transitionStart),
                0
            ),
            1
        )
        let smoothProgress = progress * progress * (3 - 2 * progress)
        return 1 - smoothProgress * 0.48
    }
}

enum RhythmPulseAppearanceMode: Sendable {
    case light
    case dark
}

enum RhythmPulseBlendStrategy: Sendable {
    case multiply
    case screen
}

struct RhythmPulseAppearance: Sendable {
    let colors: [RhythmPulseColor]
    let washBlendStrategy: RhythmPulseBlendStrategy
    let usesDarkBackdrop: Bool

    static func resolve(
        mode: RhythmPulseAppearanceMode,
        palette: RhythmAccentPalette
    ) -> RhythmPulseAppearance {
        switch mode {
        case .light:
            RhythmPulseAppearance(
                colors: palette.colors,
                washBlendStrategy: .multiply,
                usesDarkBackdrop: false
            )
        case .dark:
            RhythmPulseAppearance(
                colors: palette.colors,
                washBlendStrategy: .screen,
                usesDarkBackdrop: false
            )
        }
    }
}

struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private func smootherStep(_ progress: Double) -> Double {
    let value = min(max(progress, 0), 1)
    return value * value * value
        * (value * (value * 6 - 15) + 10)
}

private func rhythmImpactEase(_ progress: Double) -> Double {
    let target = min(max(progress, 0), 1)
    guard target > 0 else {
        return 0
    }
    guard target < 1 else {
        return 1
    }
    var lowerBound = 0.0
    var upperBound = 1.0
    for _ in 0 ..< 14 {
        let parameter = (lowerBound + upperBound) * 0.5
        if cubicBezierCoordinate(parameter, control1: 0.1, control2: 0.14) < target {
            lowerBound = parameter
        } else {
            upperBound = parameter
        }
    }
    return cubicBezierCoordinate(
        (lowerBound + upperBound) * 0.5,
        control1: 0.76,
        control2: 1
    )
}

private func cubicBezierCoordinate(
    _ parameter: Double,
    control1: Double,
    control2: Double
) -> Double {
    let inverse = 1 - parameter
    return 3 * inverse * inverse * parameter * control1
        + 3 * inverse * parameter * parameter * control2
        + parameter * parameter * parameter
}

private func random(
    in range: ClosedRange<Double>,
    using generator: inout some RandomNumberGenerator
) -> Double {
    let unit = Double(generator.next()) / Double(UInt64.max)
    return range.lowerBound + unit * (range.upperBound - range.lowerBound)
}

private func randomElement<Element>(
    in elements: [Element],
    using generator: inout some RandomNumberGenerator
) -> Element {
    let index = Int(generator.next() % UInt64(elements.count))
    return elements[index]
}

private func randomID(
    using generator: inout some RandomNumberGenerator
) -> UInt64 {
    generator.next()
}
