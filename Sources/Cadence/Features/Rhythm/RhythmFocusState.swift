import Foundation

enum RhythmFocusAction: Equatable, Sendable {
    case none
    case activated
    case extended
    case deactivated
}

struct RhythmFocusState: Sendable {
    static let chordWindow: TimeInterval = 0.18
    static let inactivityDuration: TimeInterval = 10

    private(set) var isActive = false
    private(set) var deadline: TimeInterval?
    private var previousHit: (lane: RhythmLane, time: TimeInterval)?

    mutating func registerHit(
        lane: RhythmLane,
        at time: TimeInterval
    ) -> RhythmFocusAction {
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

    mutating func update(at time: TimeInterval) -> RhythmFocusAction {
        guard isActive, let deadline, time >= deadline else {
            return .none
        }
        return deactivate()
    }

    @discardableResult
    mutating func deactivate() -> RhythmFocusAction {
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
