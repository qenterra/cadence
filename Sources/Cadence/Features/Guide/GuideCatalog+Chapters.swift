extension GuideCatalog {
    static let libraryAndImport = GuideChapter(
        id: .libraryAndImport,
        steps: [
            GuideStep(
                id: "library.sidebar",
                title: "Library Destinations",
                message: "Use the sidebar to switch between the focused Library "
                    + "view, All Tracks, Albums, and Artists.",
                anchor: .sidebar,
                route: .destination(.library),
                placement: .trailing
            ),
            GuideStep(
                id: "library.columns",
                title: "Artist to Album to Track",
                message: "The Library keeps its three-column hierarchy stable "
                    + "while you move through your collection.",
                anchor: .library,
                route: .destination(.library)
            ),
            GuideStep(
                id: "library.all-tracks",
                title: "The Complete Catalog",
                message: "All Tracks gathers the production catalog into one "
                    + "paged, searchable view.",
                anchor: .allTracks,
                route: .destination(.allTracks),
                placement: .below
            ),
            GuideStep(
                id: "library.track-table",
                title: "Shape the Track Table",
                message: "Select visible columns from the ellipsis, drag edges "
                    + "to resize, and select a heading to change sorting.",
                anchor: .trackTable,
                route: .destination(.allTracks),
                unavailableMessage: "Import music to populate the track table."
            ),
            GuideStep(
                id: "library.import",
                title: "Scan, Review, Import",
                message: "Cadence reads metadata and duplicate evidence first. "
                    + "Only your approved selection is copied.",
                anchor: .importMusic,
                route: .destination(.importMusic),
                placement: .below
            ),
        ]
    )

    static let playbackAndLyrics = GuideChapter(
        id: .playbackAndLyrics,
        steps: [
            GuideStep(
                id: "playback.player-bar",
                title: "Playback Everywhere",
                message: "Transport controls, timeline, volume, output, audio "
                    + "profile, and queue remain available across Cadence.",
                anchor: .playerBar,
                placement: .above
            ),
            GuideStep(
                id: "playback.now-playing",
                title: "A Listening Workspace",
                message: "Now Playing combines large artwork, linked metadata, "
                    + "tags, audio-path details, and the active side panel.",
                anchor: .nowPlaying,
                route: .nowPlaying(.queue),
                unavailableMessage: "Start a track to open Now Playing."
            ),
            GuideStep(
                id: "playback.queue",
                title: "Control What Plays Next",
                message: "Choose a queued track immediately, reorder upcoming "
                    + "music, or remove entries without leaving Now Playing.",
                anchor: .queue,
                route: .nowPlaying(.queue),
                unavailableMessage: "The queue appears after playback starts."
            ),
            GuideStep(
                id: "playback.lyrics",
                title: "Follow Every Line",
                message: "Timed lyrics follow playback smoothly. Selecting a "
                    + "synchronized line seeks to that moment.",
                anchor: .lyrics,
                route: .nowPlaying(.lyrics),
                unavailableMessage: "Lyrics appear for tracks with managed LRC."
            ),
            GuideStep(
                id: "playback.lyrics-editor",
                title: "Build and Repair Timing",
                message: "The Lyrics Editor supports line text, timestamps, "
                    + "tap-to-sync, validation, and managed LRC persistence.",
                anchor: .lyricsEditor,
                route: .lyricsEditor,
                unavailableMessage: "Select or play a track to edit its lyrics."
            ),
        ]
    )

    static let tagsAndCollections = GuideChapter(
        id: .tagsAndCollections,
        steps: [
            GuideStep(
                id: "organize.tags",
                title: "Tags That Match Your Music",
                message: "Create standalone tags or paths such as genre/ambient. "
                    + "Assign them without rewriting audio files.",
                anchor: .tags,
                route: .destination(.tags)
            ),
            GuideStep(
                id: "organize.smart-collections",
                title: "Collections That Stay Current",
                message: "Combine nested rules for tags, favorites, years, "
                    + "formats, and playback history. Results stay current.",
                anchor: .smartCollections,
                route: .destination(.smartCollections)
            ),
        ]
    )

    static let playlists = GuideChapter(
        id: .playlists,
        steps: [
            GuideStep(
                id: "playlists.overview",
                title: "Your Listening Order",
                message: "Create and rename playlists, add music from context "
                    + "menus, and drag tracks into the order you want.",
                anchor: .playlists,
                route: .destination(.playlists)
            ),
            GuideStep(
                id: "playlists.playback",
                title: "Play or Shuffle",
                message: "Each playlist has its own queue source plus Play and "
                    + "Shuffle controls.",
                anchor: .playlists,
                route: .destination(.playlists)
            ),
        ]
    )

    static let settingsAndCustomization = GuideChapter(
        id: .settingsAndCustomization,
        steps: [
            GuideStep(
                id: "settings.preferences",
                title: "Playback and Appearance",
                message: "Choose Adaptive, Pure, or Immersive playback and let "
                    + "Cadence follow the system appearance or Light or Dark.",
                anchor: .settings,
                route: .destination(.settings),
                placement: .below
            ),
            GuideStep(
                id: "settings.sidebar",
                title: "A Sidebar That Fits",
                message: "Reorder visible destinations by dragging them in "
                    + "Settings, and hide sections you do not use.",
                anchor: .sidebarSettings,
                route: .destination(.settings)
            ),
        ]
    )
}
