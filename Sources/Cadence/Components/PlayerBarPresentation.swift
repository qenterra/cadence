import QenTerraDesignTokens

enum PlayerControlVisualState: CaseIterable, Sendable {
    case normal
    case active
    case disabled

    var token: QDSColorValue {
        switch self {
        case .normal, .active:
            QDS.Color.textPrimary
        case .disabled:
            QDS.Color.textSecondary
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
