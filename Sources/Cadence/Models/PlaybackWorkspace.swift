import Foundation

enum PlaybackWorkspace: Hashable, Sendable {
    case hidden
    case nowPlaying
    case lyricsEditor
    case lyricsSearch
}

enum NowPlayingPanel: String, CaseIterable, Identifiable, Sendable {
    case lyrics
    case queue

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .lyrics: String(localized: "Lyrics")
        case .queue: String(localized: "Queue")
        }
    }
}

enum LyricsTransitionTarget: Hashable, Sendable {
    case closeEditor
    case destination(NavigationDestination)
    case nowPlayingPanel(NowPlayingPanel)
    case playbackOffset(Int)
}

enum LyricsDraftResolution: Hashable, Sendable {
    case save
    case discard
    case cancel
}
