import Foundation
import Observation

@MainActor
@Observable
final class CadenceModeSession {
    let pulseStore = RhythmPulseStore()
    private(set) var isActive = false
    private(set) var activationIsPending = false

    @ObservationIgnored private var inputState = CadenceModeInputState()
    @ObservationIgnored private let automatesTiming: Bool
    @ObservationIgnored private let deadlineController =
        CadenceModeDeadlineController()
    @ObservationIgnored private var layout = CadenceModeLayout(
        canvasSize: .zero,
        contextWidth: 0
    )

    init(automatesTiming: Bool = true) {
        self.automatesTiming = automatesTiming
    }

    @discardableResult
    func keyDown(
        lane: RhythmLane,
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime,
        canActivate: Bool
    ) -> CadenceModeInputAction {
        var nextState = inputState
        let action = nextState.keyDown(
            lane: lane,
            at: time,
            canActivate: canActivate
        )
        inputState = nextState
        publishPresentationState()

        if case let .emit(lane) = action {
            emitPulse(lane: lane)
        }
        scheduleDeadlineIfNeeded()
        return action
    }

    func keyUp(lane: RhythmLane) {
        var nextState = inputState
        nextState.keyUp(lane: lane)
        inputState = nextState
        publishPresentationState()
    }

    func releaseAllKeys() {
        var nextState = inputState
        nextState.releaseAllKeys()
        inputState = nextState
        publishPresentationState()
    }

    func setStaysActive(
        _ staysActive: Bool,
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        var nextState = inputState
        nextState.setTimeoutPolicy(
            staysActive
                ? .persistent
                : .inactivity(CadenceModeState.inactivityDuration),
            at: time
        )
        inputState = nextState
        scheduleDeadlineIfNeeded()
    }

    func setPresentationAvailable(
        _ isAvailable: Bool,
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        var nextState = inputState
        nextState.setPresentationAvailable(isAvailable, at: time)
        inputState = nextState
        publishPresentationState()
        if nextState.isActive {
            scheduleDeadlineIfNeeded()
        }
    }

    func updateLayout(_ layout: CadenceModeLayout) {
        self.layout = layout
    }

    func currentTrackDidChange() {
        pulseStore.reset()
    }

    func deactivate() {
        var nextState = inputState
        _ = nextState.deactivate()
        inputState = nextState
        publishPresentationState()
        deadlineController.cancel()
        pulseStore.reset()
    }

    private func emitPulse(lane: RhythmLane) {
        pulseStore.registerHit(
            lane: lane,
            emitterOrigin: layout.normalizedEmitterOrigin(
                lane: lane,
                isCadenceModeActive: true
            )
        )
    }

    private func scheduleDeadlineIfNeeded() {
        guard automatesTiming else {
            return
        }
        guard let deadline = inputState.deadline else {
            deadlineController.cancel()
            return
        }
        deadlineController.schedule(deadline: deadline) { [weak self] in
            guard let self else {
                return
            }
            var nextState = inputState
            guard nextState.update(
                at: ProcessInfo.processInfo.systemUptime
            ) == .deactivated else {
                return
            }
            inputState = nextState
            publishPresentationState()
            pulseStore.reset()
        }
    }

    private func publishPresentationState() {
        if isActive != inputState.isActive {
            isActive = inputState.isActive
        }
        if activationIsPending != inputState.activationIsPending {
            activationIsPending = inputState.activationIsPending
        }
    }
}
