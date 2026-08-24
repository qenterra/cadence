import Foundation

enum LyricsScrollAction: Equatable, Sendable {
    case none
    case top
    case activeLine(id: LyricLine.ID, duration: TimeInterval)
}

struct LyricsScrollPresentation: Equatable, Sendable {
    static let followDuration: TimeInterval = 0.32

    private var trackID: UUID?
    private var activeLineID: LyricLine.ID?

    mutating func resolve(
        trackID: UUID,
        activeLineID: LyricLine.ID?,
        reduceMotion: Bool
    ) -> LyricsScrollAction {
        guard self.trackID == trackID else {
            self.trackID = trackID
            self.activeLineID = activeLineID
            return .top
        }

        guard activeLineID != self.activeLineID else {
            return .none
        }
        self.activeLineID = activeLineID
        guard let activeLineID else {
            return .none
        }
        return .activeLine(
            id: activeLineID,
            duration: reduceMotion ? 0 : Self.followDuration
        )
    }
}

enum LyricsScrollTarget: Hashable, Sendable {
    case top
}

struct LyricsScrollObservation: Equatable, Sendable {
    let trackID: UUID
    let activeLineID: LyricLine.ID?
    let reduceMotion: Bool
}
