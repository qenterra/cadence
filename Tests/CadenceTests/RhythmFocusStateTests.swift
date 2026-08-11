@testable import Cadence
import Testing

struct RhythmFocusStateTests {
    @Test("Opposite lanes inside the chord window activate focus")
    func oppositeLanesActivateFocus() {
        var state = RhythmFocusState()

        #expect(state.registerHit(lane: .left, at: 4) == .none)
        #expect(state.registerHit(lane: .right, at: 4.18) == .activated)
        #expect(state.isActive)
        #expect(state.deadline == 14.18)
    }

    @Test("A slow or repeated lane pair does not activate focus")
    func invalidPairsDoNotActivateFocus() {
        var slowPair = RhythmFocusState()
        var repeatedLane = RhythmFocusState()

        #expect(slowPair.registerHit(lane: .left, at: 2) == .none)
        #expect(slowPair.registerHit(lane: .right, at: 2.181) == .none)
        #expect(!slowPair.isActive)

        #expect(repeatedLane.registerHit(lane: .left, at: 7) == .none)
        #expect(repeatedLane.registerHit(lane: .left, at: 7.1) == .none)
        #expect(!repeatedLane.isActive)
    }

    @Test("Every focused hit restarts the ten-second deadline")
    func focusedHitRestartsDeadline() {
        var state = RhythmFocusState()
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
        var state = RhythmFocusState()
        _ = state.registerHit(lane: .left, at: 0)
        _ = state.registerHit(lane: .right, at: 0.1)
        _ = state.update(at: 10.1)

        #expect(state.registerHit(lane: .right, at: 10.2) == .none)
        #expect(state.registerHit(lane: .left, at: 10.3) == .activated)
        #expect(state.isActive)
    }

    @Test("Reset clears active focus and chord history")
    func resetClearsFocusAndChordHistory() {
        var state = RhythmFocusState()
        _ = state.registerHit(lane: .left, at: 3)
        _ = state.registerHit(lane: .right, at: 3.1)

        state.reset()

        #expect(!state.isActive)
        #expect(state.deadline == nil)
        #expect(state.registerHit(lane: .left, at: 3.15) == .none)
    }
}
