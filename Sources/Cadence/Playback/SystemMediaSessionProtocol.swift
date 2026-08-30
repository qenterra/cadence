import Foundation

enum SystemMediaCommand: Equatable, Sendable {
    case changePosition(TimeInterval)
    case next
    case pause
    case play
    case previous
    case skipBackward(TimeInterval)
    case skipForward(TimeInterval)
    case toggle
}

/// Bridges system media controls and Now Playing metadata to the coordinator.
///
/// The bridge forwards commands but owns no playback state. `shutdown` must
/// remove command handlers so a discarded coordinator cannot receive events.
@MainActor
protocol SystemMediaSessionControlling: AnyObject {
    func activate(
        handler: @escaping (SystemMediaCommand) -> Void
    )
    func update(state: PlaybackCoordinatorState)
    func setSkipInterval(_ interval: TimeInterval)
    func clear()
    func shutdown()
}

extension SystemMediaSessionControlling {
    func setSkipInterval(_: TimeInterval) {}
}
