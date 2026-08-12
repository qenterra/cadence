import Foundation

enum CadenceModeAction: Equatable, Sendable {
    case none
    case activated
    case extended
    case deactivated
}

enum CadenceModeHitResponse: Equatable, Sendable {
    case none
    case activate
    case emitPulse

    static func resolve(
        wasActive: Bool,
        stateAction: CadenceModeAction
    ) -> CadenceModeHitResponse {
        if wasActive {
            return .emitPulse
        }
        return stateAction == .activated ? .activate : .none
    }
}

enum CadenceModeInputAction: Equatable, Sendable {
    case none
    case requestPresentation
    case emit(RhythmLane)
}

struct CadenceModeInputState: Sendable {
    private var modeState = CadenceModeState()
    private var heldLanes: Set<RhythmLane> = []
    private var presentationAvailable = false

    var isActive: Bool {
        modeState.isActive && presentationAvailable
    }

    var activationIsPending: Bool {
        modeState.isActive && !presentationAvailable
    }

    var deadline: TimeInterval? {
        modeState.deadline
    }

    mutating func keyDown(
        lane: RhythmLane,
        at time: TimeInterval,
        canActivate: Bool
    ) -> CadenceModeInputAction {
        guard heldLanes.insert(lane).inserted else {
            return .none
        }
        guard modeState.isActive || canActivate else {
            return .none
        }

        let wasActive = modeState.isActive
        let action = modeState.registerHit(lane: lane, at: time)
        if wasActive {
            return presentationAvailable ? .emit(lane) : .none
        }
        return action == .activated ? .requestPresentation : .none
    }

    mutating func keyUp(lane: RhythmLane) {
        heldLanes.remove(lane)
    }

    mutating func releaseAllKeys() {
        heldLanes.removeAll(keepingCapacity: true)
    }

    mutating func setPresentationAvailable(
        _ isAvailable: Bool,
        at _: TimeInterval
    ) {
        guard presentationAvailable != isAvailable else {
            return
        }
        presentationAvailable = isAvailable
        if isAvailable {
            releaseAllKeys()
        }
    }

    mutating func update(at time: TimeInterval) -> CadenceModeAction {
        let action = modeState.update(at: time)
        if action == .deactivated {
            presentationAvailable = false
            releaseAllKeys()
        }
        return action
    }

    @discardableResult
    mutating func deactivate() -> CadenceModeAction {
        let action = modeState.deactivate()
        presentationAvailable = false
        releaseAllKeys()
        return action
    }
}

struct CadenceModeState: Sendable {
    static let chordWindow: TimeInterval = 0.18
    static let inactivityDuration: TimeInterval = 10

    private(set) var isActive = false
    private(set) var deadline: TimeInterval?
    private var previousHit: (lane: RhythmLane, time: TimeInterval)?

    mutating func registerHit(
        lane: RhythmLane,
        at time: TimeInterval
    ) -> CadenceModeAction {
        defer {
            previousHit = (lane, time)
        }

        if isActive {
            deadline = time + Self.inactivityDuration
            return .extended
        }

        guard
            let previousHit,
            previousHit.lane != lane,
            time >= previousHit.time,
            time - previousHit.time <= Self.chordWindow
        else {
            return .none
        }

        isActive = true
        deadline = time + Self.inactivityDuration
        return .activated
    }

    mutating func update(at time: TimeInterval) -> CadenceModeAction {
        guard isActive, let deadline, time >= deadline else {
            return .none
        }
        return deactivate()
    }

    @discardableResult
    mutating func deactivate() -> CadenceModeAction {
        guard isActive else {
            return .none
        }
        isActive = false
        deadline = nil
        previousHit = nil
        return .deactivated
    }

    mutating func reset() {
        isActive = false
        deadline = nil
        previousHit = nil
    }
}

@MainActor
final class CadenceModeDeadlineController {
    private var task: Task<Void, Never>?

    func schedule(
        deadline: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) {
        task?.cancel()
        task = Task { @MainActor in
            let delay = max(
                deadline - ProcessInfo.processInfo.systemUptime,
                0
            )
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
