import Foundation

enum GuideChapterID: String, CaseIterable, Identifiable, Sendable {
    case essentials
    case libraryAndImport
    case playbackAndLyrics
    case tagsAndCollections
    case playlists
    case settingsAndCustomization

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .essentials: "Cadence Essentials"
        case .libraryAndImport: "Library & Import"
        case .playbackAndLyrics: "Playback & Lyrics"
        case .tagsAndCollections: "Tags & Collections"
        case .playlists: "Playlists"
        case .settingsAndCustomization: "Settings & Customization"
        }
    }

    var subtitle: String {
        switch self {
        case .essentials:
            "A quick tour of the complete Cadence workflow."
        case .libraryAndImport:
            "Bring music in, browse it, and shape the track table."
        case .playbackAndLyrics:
            "Use the player, queue, Now Playing, and line-timed lyrics."
        case .tagsAndCollections:
            "Organize music with tags and rule-based collections."
        case .playlists:
            "Build listening-first collections in your own order."
        case .settingsAndCustomization:
            "Adjust playback, appearance, and the navigation sidebar."
        }
    }

    var symbolName: String {
        switch self {
        case .essentials: "sparkles"
        case .libraryAndImport: "books.vertical"
        case .playbackAndLyrics: "play.square.stack"
        case .tagsAndCollections: "tag"
        case .playlists: "music.note.list"
        case .settingsAndCustomization: "slider.horizontal.3"
        }
    }
}

enum GuideAnchor: String, Hashable, Sendable {
    case sidebar
    case sidebarSettings
    case library
    case allTracks
    case trackTable
    case importMusic
    case playerBar
    case nowPlaying
    case queue
    case lyrics
    case lyricsEditor
    case tags
    case smartCollections
    case playlists
    case settings
}

enum GuideCardPlacement: Hashable, Sendable {
    case automatic
    case center
    case above
    case below
    case leading
    case trailing
}

enum GuideRoute: Hashable, Sendable {
    case destination(NavigationDestination)
    case nowPlaying(NowPlayingPanel)
    case lyricsEditor
}

struct GuideStep: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let message: String
    let anchor: GuideAnchor
    let route: GuideRoute?
    let placement: GuideCardPlacement
    let unavailableMessage: String?

    init(
        id: String,
        title: String,
        message: String,
        anchor: GuideAnchor,
        route: GuideRoute? = nil,
        placement: GuideCardPlacement = .automatic,
        unavailableMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.anchor = anchor
        self.route = route
        self.placement = placement
        self.unavailableMessage = unavailableMessage
    }

    func displayedMessage(hasResolvedAnchor: Bool) -> String {
        guard !hasResolvedAnchor else {
            return message
        }
        return unavailableMessage ?? message
    }
}

struct GuideChapter: Identifiable, Hashable, Sendable {
    let id: GuideChapterID
    let steps: [GuideStep]
}

enum GuideCatalog {
    static let onboardingVersion = 1

    static let allChapters: [GuideChapter] = [
        essentials,
        libraryAndImport,
        playbackAndLyrics,
        tagsAndCollections,
        playlists,
        settingsAndCustomization,
    ]

    static func chapter(_ id: GuideChapterID) -> GuideChapter {
        allChapters.first { $0.id == id } ?? essentials
    }

    static let essentials = GuideChapter(
        id: .essentials,
        steps: [
            GuideStep(
                id: "essentials.sidebar",
                title: "Find Your Way",
                message: "The sidebar keeps every part of Cadence close. "
                    + "Expand it for labels or keep the compact icon view.",
                anchor: .sidebar,
                route: .destination(.library),
                placement: .trailing
            ),
            GuideStep(
                id: "essentials.library",
                title: "Browse Your Library",
                message: "Move from artists to albums to tracks without "
                    + "losing your place. Artwork and metadata stay connected.",
                anchor: .library,
                route: .destination(.library)
            ),
            GuideStep(
                id: "essentials.all-tracks",
                title: "Every Track, Your Way",
                message: "All Tracks provides a sortable table with resizable, "
                    + "configurable columns and quick access to track actions.",
                anchor: .allTracks,
                route: .destination(.allTracks),
                placement: .below
            ),
            GuideStep(
                id: "essentials.import",
                title: "Bring In Your Music",
                message: "Choose files or a folder, or drop music into Cadence. "
                    + "You review the scan before anything is copied.",
                anchor: .importMusic,
                route: .destination(.importMusic),
                placement: .below
            ),
            GuideStep(
                id: "essentials.player",
                title: "Playback Stays Close",
                message: "The Player Bar controls playback, seeking, volume, "
                    + "quality profile, audio output, and the active queue.",
                anchor: .playerBar,
                placement: .above
            ),
            GuideStep(
                id: "essentials.now-playing",
                title: "Now Playing and Queue",
                message: "Open the current track to see its artwork, metadata, "
                    + "tags, lyrics, and queue in one listening workspace.",
                anchor: .nowPlaying,
                route: .nowPlaying(.queue),
                unavailableMessage: "Start a track to open Now Playing and manage its active queue."
            ),
            GuideStep(
                id: "essentials.lyrics",
                title: "Line-Timed Lyrics",
                message: "Cadence follows synchronized LRC lines and lets you seek by selecting a timed line.",
                anchor: .lyrics,
                route: .nowPlaying(.lyrics),
                unavailableMessage: "Play a track with an LRC file to follow line-timed lyrics here."
            ),
            GuideStep(
                id: "essentials.organize",
                title: "Organize Beyond Folders",
                message: "Assign standalone or hierarchical tags, then turn "
                    + "those relationships into collections and playlists.",
                anchor: .tags,
                route: .destination(.tags)
            ),
            GuideStep(
                id: "essentials.settings",
                title: "Tune Cadence to You",
                message: "Choose a playback profile, appearance, and sidebar "
                    + "order. Replay any chapter from the Help menu.",
                anchor: .settings,
                route: .destination(.settings),
                placement: .below
            ),
        ]
    )
}
