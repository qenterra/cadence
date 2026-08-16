import Foundation

enum PlayerControlVisualState: CaseIterable, Sendable {
    case normal
    case active
    case disabled

    var token: CadenceColorValue {
        switch self {
        case .normal, .active:
            CadenceTheme.textPrimary
        case .disabled:
            CadenceTheme.textSecondary
        }
    }
}

struct PlayerBarEmptyPresentation: Equatable, Sendable {
    let title: String
    let symbolName: String

    init(libraryTrackCount: Int) {
        if libraryTrackCount == 0 {
            title = "Open an audio file to listen"
            symbolName = "waveform"
        } else {
            title = "Select a Track"
            symbolName = "music.note"
        }
    }
}

enum PlayerTransportControl: CaseIterable, Sendable {
    case shuffle
    case previous
    case playPause
    case next
    case repeatMode
    case progress
    case queue
}

struct PlayerBarAccessibilityControl: Equatable, Sendable {
    let label: String
    let isEnabled: Bool
}

enum PlayerBarAccessibilityContract {
    static func transportControls(
        hasPlaybackItem: Bool,
        isPlaying: Bool,
        repeatMode: RepeatMode
    ) -> [PlayerBarAccessibilityControl] {
        PlayerTransportControl.allCases.map {
            control(
                $0,
                hasPlaybackItem: hasPlaybackItem,
                isPlaying: isPlaying,
                repeatMode: repeatMode
            )
        }
    }

    static func control(
        _ control: PlayerTransportControl,
        hasPlaybackItem: Bool,
        isPlaying: Bool,
        repeatMode: RepeatMode
    ) -> PlayerBarAccessibilityControl {
        let label = switch control {
        case .shuffle: String(localized: "Shuffle")
        case .previous: String(localized: "Previous Track")
        case .playPause: playPauseLabel(isPlaying: isPlaying)
        case .next: String(localized: "Next Track")
        case .repeatMode:
            switch repeatMode {
            case .off: String(localized: "Repeat Off")
            case .all: String(localized: "Repeat All")
            case .one: String(localized: "Repeat One")
            }
        case .progress: String(localized: "Playback progress")
        case .queue: String(localized: "Queue")
        }
        return PlayerBarAccessibilityControl(
            label: label,
            isEnabled: hasPlaybackItem
        )
    }

    private static func playPauseLabel(
        isPlaying: Bool
    ) -> String {
        if isPlaying {
            return String(localized: "Pause")
        }
        return String(localized: "Play")
    }
}
