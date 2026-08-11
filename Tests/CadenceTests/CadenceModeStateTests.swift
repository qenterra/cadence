@testable import Cadence
import CoreGraphics
import Foundation
import Observation
import Testing

struct CadenceModeStateTests {
    @Test("A global chord requests presentation only while playback is active")
    func globalChordRequiresActivePlayback() {
        var unavailable = CadenceModeInputState()
        var available = CadenceModeInputState()

        #expect(
            unavailable.keyDown(
                lane: .left,
                at: 1,
                canActivate: false
            ) == .none
        )
        #expect(
            unavailable.keyDown(
                lane: .right,
                at: 1.1,
                canActivate: false
            ) == .none
        )
        #expect(!unavailable.isActive)

        #expect(
            available.keyDown(
                lane: .left,
                at: 2,
                canActivate: true
            ) == .none
        )
        #expect(
            available.keyDown(
                lane: .right,
                at: 2.1,
                canActivate: true
            ) == .requestPresentation
        )
        #expect(available.activationIsPending)
        #expect(!available.isActive)
    }

    @Test("Held keys emit only after a new physical press")
    func heldKeysDoNotRepeat() {
        var state = CadenceModeInputState()
        _ = state.keyDown(lane: .left, at: 3, canActivate: true)
        _ = state.keyDown(lane: .right, at: 3.1, canActivate: true)
        state.setPresentationAvailable(true, at: 3.4)

        #expect(state.isActive)
        #expect(
            state.keyDown(lane: .left, at: 30, canActivate: true) == .none
        )
        #expect(
            state.keyDown(lane: .right, at: 31, canActivate: true) == .none
        )
        state.keyUp(lane: .left)
        #expect(
            state.keyDown(lane: .left, at: 32, canActivate: true)
                == .emit(.left)
        )
        #expect(
            state.keyDown(lane: .left, at: 33, canActivate: true) == .none
        )
    }

    @MainActor
    @Test("The root Cadence session keeps running while artwork changes")
    func rootSessionSurvivesArtworkChange() {
        let session = CadenceModeSession(automatesTiming: false)
        session.pulseStore.prepare(
            visualQAState: RhythmPulseVisualQAState(
                palette: RhythmAccentPalette(
                    colors: [
                        RhythmPulseColor(red: 0.9, green: 0.2, blue: 0.5),
                    ]
                ),
                seed: 41,
                lanes: []
            )
        )
        session.updateLayout(
            CadenceModeLayout(
                canvasSize: CGSize(width: 1200, height: 760),
                contextWidth: 480
            )
        )
        _ = session.keyDown(lane: .left, at: 6, canActivate: true)
        #expect(
            session.keyDown(
                lane: .right,
                at: 6.1,
                canActivate: true
            ) == .requestPresentation
        )
        session.setPresentationAvailable(true, at: 6.1)

        session.currentTrackDidChange()

        #expect(session.isActive)
        session.keyUp(lane: .left)
        #expect(
            session.keyDown(
                lane: .left,
                at: 6.2,
                canActivate: false
            ) == .emit(.left)
        )
        #expect(!session.pulseStore.renderParticles.isEmpty)
    }

    @MainActor
    @Test("The root session requires key release before another effect")
    func rootSessionRequiresDiscretePresses() {
        let session = CadenceModeSession(automatesTiming: false)
        _ = session.keyDown(lane: .left, at: 7, canActivate: true)
        _ = session.keyDown(lane: .right, at: 7.1, canActivate: true)
        session.setPresentationAvailable(true, at: 7.1)

        #expect(
            session.keyDown(lane: .left, at: 7.32, canActivate: true)
                == .none
        )
        session.keyUp(lane: .left)
        #expect(
            session.keyDown(lane: .left, at: 7.5, canActivate: true)
                == .emit(.left)
        )
        #expect(session.pulseStore.renderParticles.count >= 4)
    }

    @MainActor
    @Test("Holding Cadence keys never synthesizes effects")
    func holdingKeysDoesNotSynthesizeEffects() async throws {
        let session = CadenceModeSession()
        let now = ProcessInfo.processInfo.systemUptime
        _ = session.keyDown(lane: .left, at: now, canActivate: true)
        _ = session.keyDown(lane: .right, at: now + 0.1, canActivate: true)
        session.setPresentationAvailable(true, at: now + 0.1)

        try await Task.sleep(for: .milliseconds(500))

        #expect(session.pulseStore.renderParticles.isEmpty)
        #expect(session.pulseStore.renderWashes.isEmpty)
        session.deactivate()
    }

    @MainActor
    @Test("Ignored held-key events do not invalidate session presentation")
    func ignoredHeldKeysDoNotInvalidatePresentation() {
        let session = CadenceModeSession(automatesTiming: false)
        _ = session.keyDown(lane: .left, at: 8, canActivate: true)
        _ = session.keyDown(lane: .right, at: 8.1, canActivate: true)
        session.setPresentationAvailable(true, at: 8.1)

        let presentationInvalidations = ObservationInvalidationCounter()
        withObservationTracking {
            _ = session.isActive
            _ = session.activationIsPending
        } onChange: {
            presentationInvalidations.increment()
        }

        #expect(
            session.keyDown(lane: .left, at: 8.32, canActivate: true)
                == .none
        )
        #expect(presentationInvalidations.value == 0)
    }

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

private final class ObservationInvalidationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock {
            count += 1
        }
    }
}
