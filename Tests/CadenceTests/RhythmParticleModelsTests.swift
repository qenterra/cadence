@testable import Cadence
import Foundation
import Testing

struct RhythmParticleModelsTests {
    @MainActor
    @Test("The live pulse store registers and clears an emitter burst")
    func pulseStoreOwnsParticleLifetime() {
        let store = RhythmPulseStore()
        store.prepare(
            visualQAState: RhythmPulseVisualQAState(
                palette: .particleFixture,
                seed: 97,
                lanes: []
            )
        )

        store.registerHit(
            lane: .left,
            emitterOrigin: CGPoint(x: 0.3, y: 0.6)
        )

        #expect((20 ... 24).contains(store.renderParticles.count))
        #expect(store.renderParticles.allSatisfy {
            $0.origin == CGPoint(x: 0.3, y: 0.6)
        })
        store.reset()
        #expect(store.renderParticles.isEmpty)
    }

    @Test("A hit emits a varied compact particle burst from its artwork origin")
    func hitEmitsVariedBurst() {
        var simulation = RhythmParticleSimulation()
        var random = SplitMix64(seed: 101)
        let origin = CGPoint(x: 0.24, y: 0.62)

        simulation.registerHit(
            lane: .left,
            origin: origin,
            palette: .particleFixture,
            time: 5,
            generator: &random
        )

        let particles = simulation.allParticles
        #expect((20 ... 24).contains(particles.count))
        #expect(particles.allSatisfy { $0.origin == origin })
        #expect(particles.allSatisfy {
            (-0.02 ... 0.02).contains($0.emissionOffset.dx)
                && (-0.025 ... 0.025).contains($0.emissionOffset.dy)
        })
        #expect(Set(particles.map(\.size)).count > 4)
        #expect(Set(particles.map(\.lifetime)).count > 4)
        #expect(particles.allSatisfy {
            (0.7 ... 1.55).contains($0.lifetime)
        })
        #expect(particles.allSatisfy { (5 ... 5.12).contains($0.startedAt) })
    }

    @Test("Left and right emitters launch outward in broad mirrored fans")
    func lanesUseDistinctOutwardCones() {
        var leftSimulation = RhythmParticleSimulation()
        var rightSimulation = RhythmParticleSimulation()
        var leftRandom = SplitMix64(seed: 107)
        var rightRandom = SplitMix64(seed: 109)

        leftSimulation.registerHit(
            lane: .left,
            origin: CGPoint(x: 0.2, y: 0.6),
            palette: .particleFixture,
            time: 0,
            generator: &leftRandom
        )
        rightSimulation.registerHit(
            lane: .right,
            origin: CGPoint(x: 0.3, y: 0.6),
            palette: .particleFixture,
            time: 0,
            generator: &rightRandom
        )

        let left = leftSimulation.allParticles
        let right = rightSimulation.allParticles
        #expect(left.allSatisfy { $0.velocity.dx < 0 })
        #expect(right.allSatisfy { $0.velocity.dx > 0 })
        #expect(left.contains { $0.velocity.dy < 0 })
        #expect(left.contains { $0.velocity.dy > 0 })
        #expect(right.contains { $0.velocity.dy < 0 })
        #expect(right.contains { $0.velocity.dy > 0 })
    }

    @Test("A rapid second hit preserves particles waiting for their delay")
    func rapidHitPreservesPendingParticles() {
        var simulation = RhythmParticleSimulation()
        var random = SplitMix64(seed: 111)
        simulation.registerHit(
            lane: .left,
            origin: CGPoint(x: 0.2, y: 0.6),
            palette: .particleFixture,
            time: 1,
            generator: &random
        )
        let pendingLeftIDs = Set(
            simulation.allParticles
                .filter { $0.startedAt > 1 }
                .map(\.id)
        )

        simulation.registerHit(
            lane: .right,
            origin: CGPoint(x: 0.8, y: 0.6),
            palette: .particleFixture,
            time: 1,
            generator: &random
        )

        #expect(!pendingLeftIDs.isEmpty)
        #expect(
            pendingLeftIDs.isSubset(
                of: Set(simulation.allParticles.map(\.id))
            )
        )
    }

    @Test("Particles keep moving after key release and settle into dust")
    func particlesContinueBallistically() throws {
        var simulation = RhythmParticleSimulation()
        var random = SplitMix64(seed: 113)
        simulation.registerHit(
            lane: .right,
            origin: CGPoint(x: 0.4, y: 0.7),
            palette: .particleFixture,
            time: 2,
            generator: &random
        )
        let particle = try #require(simulation.allParticles.first)
        let early = try #require(particle.sample(at: 2.08))
        let late = try #require(particle.sample(at: 2.48))

        #expect(early.position.x > particle.origin.x)
        #expect(late.position.x > early.position.x)
        #expect(late.shardAmount < early.shardAmount)
        #expect(late.size < early.size)
        #expect(
            particle.sample(
                at: particle.startedAt + particle.lifetime
            ) == nil
        )
    }

    @Test("Analytic particle motion stays continuous at 60 Hz")
    func particleMotionIsFrameContinuous() throws {
        var simulation = RhythmParticleSimulation()
        var random = SplitMix64(seed: 127)
        simulation.registerHit(
            lane: .left,
            origin: CGPoint(x: 0.3, y: 0.65),
            palette: .particleFixture,
            time: 0,
            generator: &random
        )
        let particle = try #require(simulation.allParticles.first)
        let samples = (1 ... 30).compactMap {
            particle.sample(at: Double($0) / 60)
        }
        let largestStep = zip(samples, samples.dropFirst()).map {
            hypot(
                $1.position.x - $0.position.x,
                $1.position.y - $0.position.y
            )
        }.max() ?? 0
        let largestOpacityStep = zip(samples, samples.dropFirst()).map {
            abs($1.opacity - $0.opacity)
        }.max() ?? 0

        #expect(largestStep < 0.02)
        #expect(largestOpacityStep < 0.22)
    }

    @Test("A thousand rapid hits never exceed the particle budget")
    func rapidHitsStayWithinBudget() {
        var simulation = RhythmParticleSimulation()
        var random = SplitMix64(seed: 131)

        for index in 0 ..< 1000 {
            simulation.registerHit(
                lane: index.isMultiple(of: 2) ? .left : .right,
                origin: CGPoint(x: 0.25, y: 0.6),
                palette: .particleFixture,
                time: Double(index) / 2000,
                generator: &random
            )
            #expect(simulation.allParticles.count <= 96)
        }
    }

    @MainActor
    @Test("The deterministic visual fixture keeps both side bursts visible")
    func visualFixtureShowsBothSides() throws {
        let store = RhythmPulseStore()
        store.prepare(
            visualQAState: RhythmPulseVisualQAState(
                palette: .particleFixture,
                seed: 0xCAD34CE,
                lanes: [.left, .right]
            )
        )
        let snapshotTime = try #require(store.visualQATime)
        let samples = store.renderParticles.compactMap { particle in
            particle.sample(at: snapshotTime).map { (particle.lane, $0) }
        }
        let leftSamples = samples.filter { $0.0 == .left }.map(\.1)
        let rightSamples = samples.filter { $0.0 == .right }.map(\.1)

        #expect(!leftSamples.isEmpty)
        #expect(!rightSamples.isEmpty)
        #expect(
            leftSamples.map(\.position.x).reduce(0, +)
                / Double(leftSamples.count) < 0.04
        )
        #expect(
            rightSamples.map(\.position.x).reduce(0, +)
                / Double(rightSamples.count) > 0.4
        )
        #expect(leftSamples.contains { $0.opacity > 0.1 })
        #expect(rightSamples.contains { $0.opacity > 0.1 })
    }

    @MainActor
    @Test("Visual QA recomputes emitter origins when focus mode changes")
    func visualFixtureUpdatesOriginsForFocus() {
        let store = RhythmPulseStore()
        let standardState = RhythmPulseVisualQAState(
            palette: .particleFixture,
            seed: 0xCAD34CE,
            lanes: [.left, .right]
        )
        let focusState = RhythmPulseVisualQAState(
            palette: .particleFixture,
            seed: 0xCAD34CE,
            lanes: [.left, .right],
            isFocusActive: true
        )

        store.prepare(visualQAState: standardState)
        store.prepare(visualQAState: focusState)

        let leftOrigins = store.renderParticles
            .filter { $0.lane == .left }
            .map(\.origin.x)
        let rightOrigins = store.renderParticles
            .filter { $0.lane == .right }
            .map(\.origin.x)
        #expect(leftOrigins.allSatisfy { $0 == 0.34 })
        #expect(rightOrigins.allSatisfy { $0 == 0.66 })
    }
}

private extension RhythmAccentPalette {
    static let particleFixture = RhythmAccentPalette(
        colors: [
            RhythmPulseColor(red: 0.94, green: 0.18, blue: 0.51),
            RhythmPulseColor(red: 0.43, green: 0.3, blue: 0.98),
            RhythmPulseColor(red: 0.02, green: 0.78, blue: 0.87),
        ]
    )
}
