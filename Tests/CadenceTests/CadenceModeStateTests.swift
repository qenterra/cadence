@testable import Cadence
import Testing

struct CadenceModeStateTests {
    @Test("Only active Cadence Mode hits emit effects")
    func hitFeedbackIsScopedToActiveMode() {
        var state = CadenceModeState()

        let firstHit = state.registerHit(lane: .left, at: 1)
        #expect(
            CadenceModeHitResponse.resolve(
                wasActive: false,
                stateAction: firstHit
            ) == .none
        )

        let activatingHit = state.registerHit(lane: .right, at: 1.1)
        #expect(
            CadenceModeHitResponse.resolve(
                wasActive: false,
                stateAction: activatingHit
            ) == .activate
        )

        let activeHit = state.registerHit(lane: .left, at: 2)
        #expect(
            CadenceModeHitResponse.resolve(
                wasActive: true,
                stateAction: activeHit
            ) == .emitPulse
        )
    }

    @MainActor
    @Test("Now Playing exposes the exact Cadence Mode hint")
    func hintCopyIsStable() {
        #expect(CadenceModeHint.copy == "Z + X — Cadence Mode")
        #expect(
            CadenceModeHint.accessibilityCopy
                == "Z plus X, Cadence Mode"
        )
    }

    @Test("Opposite lanes inside the chord window activate Cadence Mode")
    func oppositeLanesActivateCadenceMode() {
        var state = CadenceModeState()

        #expect(state.registerHit(lane: .left, at: 4) == .none)
        #expect(state.registerHit(lane: .right, at: 4.18) == .activated)
        #expect(state.isActive)
        #expect(state.deadline == 14.18)
    }

    @Test("A slow or repeated lane pair does not activate Cadence Mode")
    func invalidPairsDoNotActivateCadenceMode() {
        var slowPair = CadenceModeState()
        var repeatedLane = CadenceModeState()

        #expect(slowPair.registerHit(lane: .left, at: 2) == .none)
        #expect(slowPair.registerHit(lane: .right, at: 2.181) == .none)
        #expect(!slowPair.isActive)

        #expect(repeatedLane.registerHit(lane: .left, at: 7) == .none)
        #expect(repeatedLane.registerHit(lane: .left, at: 7.1) == .none)
        #expect(!repeatedLane.isActive)
    }

    @Test("Every Cadence Mode hit restarts the ten-second deadline")
    func cadenceModeHitRestartsDeadline() {
        var state = CadenceModeState()
        _ = state.registerHit(lane: .left, at: 1)
        _ = state.registerHit(lane: .right, at: 1.1)

        #expect(state.registerHit(lane: .left, at: 8) == .extended)
        #expect(state.deadline == 18)
        #expect(state.update(at: 17.999) == .none)
        #expect(state.isActive)
        #expect(state.update(at: 18) == .deactivated)
        #expect(!state.isActive)
    }

    @Test("A hit during exit can reactivate through a new chord")
    func hitAfterDeactivationCanReactivate() {
        var state = CadenceModeState()
        _ = state.registerHit(lane: .left, at: 0)
        _ = state.registerHit(lane: .right, at: 0.1)
        _ = state.update(at: 10.1)

        #expect(state.registerHit(lane: .right, at: 10.2) == .none)
        #expect(state.registerHit(lane: .left, at: 10.3) == .activated)
        #expect(state.isActive)
    }

    @Test("Reset clears active Cadence Mode and chord history")
    func resetClearsCadenceModeAndChordHistory() {
        var state = CadenceModeState()
        _ = state.registerHit(lane: .left, at: 3)
        _ = state.registerHit(lane: .right, at: 3.1)

        state.reset()

        #expect(!state.isActive)
        #expect(state.deadline == nil)
        #expect(state.registerHit(lane: .left, at: 3.15) == .none)
    }
}
