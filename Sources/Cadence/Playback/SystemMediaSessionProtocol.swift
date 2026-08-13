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

@MainActor
protocol SystemMediaSessionControlling: AnyObject {
    func activate(
        handler: @escaping (SystemMediaCommand) -> Void
    )
    func update(state: PlaybackCoordinatorState)
    func clear()
    func shutdown()
}
