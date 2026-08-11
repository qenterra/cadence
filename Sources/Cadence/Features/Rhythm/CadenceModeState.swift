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
