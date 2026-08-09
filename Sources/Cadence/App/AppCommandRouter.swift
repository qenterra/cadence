import Foundation

enum AppCommand: Sendable {
    case togglePlayback
    case previousTrack
    case nextTrack
    case volumeUp
    case volumeDown
}

enum AppCommandFocus: Sendable {
    case none
    case textEditing
    case menu
    case sheet
    case localControl
    case trackTable

    var blocksGlobalPlayback: Bool {
        switch self {
        case .none, .trackTable:
            false
        case .textEditing, .menu, .sheet, .localControl:
            true
        }
    }
}

@MainActor
struct AppCommandActions {
    let hasCurrentItem: () -> Bool
    let hasPlaybackFailure: () -> Bool
    let togglePlayback: () -> Void
    let previousTrack: () -> Void
    let nextTrack: () -> Void
    let adjustVolume: (Double) -> Void
}

@MainActor
struct AppCommandRouter {
    let actions: AppCommandActions

    @discardableResult
    func handle(
        _ command: AppCommand,
        focus: AppCommandFocus
    ) -> Bool {
        guard !focus.blocksGlobalPlayback else {
            return false
        }

        switch command {
        case .togglePlayback:
            guard
                actions.hasCurrentItem(),
                !actions.hasPlaybackFailure()
            else {
                return false
            }
            actions.togglePlayback()
        case .previousTrack:
            guard actions.hasCurrentItem() else {
                return false
            }
            actions.previousTrack()
        case .nextTrack:
            guard actions.hasCurrentItem() else {
                return false
            }
            actions.nextTrack()
        case .volumeUp:
            actions.adjustVolume(0.05)
        case .volumeDown:
            actions.adjustVolume(-0.05)
        }
        return true
    }
}

extension AppCommandRouter {
    init(model: CadenceAppModel) {
        self.init(
            actions: AppCommandActions(
                hasCurrentItem: {
                    model.hasCurrentPlaybackItem
                },
                hasPlaybackFailure: {
                    model.playbackCoordinator?.state.failure != nil
                },
                togglePlayback: {
                    _ = model.handlePlaybackShortcut()
                },
                previousTrack: {
                    model.moveProductionQueue(by: -1)
                },
                nextTrack: {
                    model.moveProductionQueue(by: 1)
                },
                adjustVolume: { delta in
                    model.volume = min(max(model.volume + delta, 0), 1)
                }
            )
        )
    }
}
