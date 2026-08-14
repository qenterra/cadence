import AppKit
@testable import Cadence
import SwiftData
import SwiftUI
import Testing

@MainActor
struct DocumentationScreenshotTests {
    @Test("Album capture cannot complete while album content is loading")
    func albumCaptureRequiresSemanticReadiness() async throws {
        let fixture = try await DocumentationScreenshotFixture.make()
        fixture.model.requestOpenProductionAlbumContextually(
            id: fixture.albumID
        )

        await #expect(throws: DocumentationScreenshotReadinessError.self) {
            try await fixture.waitUntilReady(
                for: .album(fixture.albumID),
                timeout: .milliseconds(50)
            )
        }
    }

    @Test("A visual mismatch produces a deterministic diff artifact")
    func mismatchedBaselineProducesDiff() throws {
        let baseline = Self.imageURL("qa-home-min-dark.png")
        let actual = Self.imageURL("qa-empty-home-min-dark.png")
        let diff = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Screenshot-Diff-\(UUID().uuidString).png"
        )
        defer { try? FileManager.default.removeItem(at: diff) }

        #expect(throws: DocumentationScreenshotComparisonError.self) {
            try DocumentationScreenshotComparator.assertMatch(
                actual: actual,
                baseline: baseline,
                diff: diff
            )
        }
        #expect(FileManager.default.fileExists(atPath: diff.path))
    }

    @Test("Render public screenshots from production projections")
    func renderProductionScreenshots() async throws {
        let navigationPreferences = NavigationScreenshotPreferences()
        navigationPreferences.install()
        defer { navigationPreferences.restore() }

        let fixture = try await DocumentationScreenshotFixture.make()
        let homePreferences = HomeScreenshotPreferences(fixture: fixture)
        homePreferences.install()
        defer { homePreferences.restore() }

        fixture.model.selectedDestination = .home
        try await fixture.captureMatrix(prefix: "home")
        try await captureLongLocalizedHome()
        try await captureEmptyHome()

        fixture.model.selectedDestination = .library
        try await fixture.capture("cadence-library.png")
        try await fixture.captureMatrix(prefix: "library")

        fixture.model.selectedDestination = .allTracks
        try await fixture.capture("qa-all-tracks-min-dark.png")
        try await fixture.capture(
            "qa-all-tracks-wide-dark.png",
            contentSize: .wide
        )

        let nowPlayingFixture = try await DocumentationScreenshotFixture.make()
        nowPlayingFixture.model.presentNowPlaying()
        nowPlayingFixture.model.selectedNowPlayingPanel = .queue
        try await nowPlayingFixture.capture("cadence-now-playing.png")
        try await nowPlayingFixture.captureMatrix(prefix: "now-playing")

        let albumFixture = try await DocumentationScreenshotFixture.make()
        albumFixture.model.requestOpenProductionAlbumContextually(
            id: albumFixture.albumID
        )
        try await albumFixture.captureMatrix(prefix: "album")

        try await fixture.captureSettings("cadence-settings.png")
        try await fixture.captureSettingsMatrix()

        let importFixture = try await DocumentationScreenshotFixture.make()
        importFixture.model.selectedDestination = .importMusic
        importFixture.model.showImportPreviewStage(.review)
        try await importFixture.captureMatrix(prefix: "import-review")

        fixture.model.selectedDestination = .tags
        fixture.model.selectedProductionTagID = fixture.tagID
        try await fixture.capture("cadence-tags.png")
    }

    private func captureEmptyHome() async throws {
        let fixture = try await DocumentationScreenshotFixture.makeEmpty()
        fixture.model.selectedDestination = .home
        for appearance in DocumentationScreenshotAppearance.allCases {
            try await fixture.capture(
                "qa-empty-home-min-\(appearance.slug).png",
                appearance: appearance
            )
        }
    }

    private func captureLongLocalizedHome() async throws {
        let fixture = try await DocumentationScreenshotFixture.make()
        let preferences = HomeScreenshotPreferences(fixture: fixture)
        preferences.install()
        defer { preferences.restore() }

        fixture.installLongLocalizedHomeMetadata()
        fixture.model.selectedDestination = .home
        try await fixture.capture("qa-home-min-long-copy-dark.png")
    }

    private static func imageURL(_ name: String) -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/images/\(name)")
    }
}

@MainActor
final class DocumentationScreenshotFixture {
    let model: CadenceAppModel
    let albumID: UUID
    let artistID: UUID
    let tagID: UUID
    let readinessTracker: DocumentationScreenshotReadinessTracker

    init(
        model: CadenceAppModel,
        albumID: UUID,
        artistID: UUID,
        tagID: UUID,
        readinessTracker: DocumentationScreenshotReadinessTracker
    ) {
        self.model = model
        self.albumID = albumID
        self.artistID = artistID
        self.tagID = tagID
        self.readinessTracker = readinessTracker
    }

    static func make() async throws -> DocumentationScreenshotFixture {
        let container = try LibraryContainerFactory.inMemory()
        let seeded = try seed(container)
        let repository = LibraryRepository(modelContainer: container)
        let session = LibrarySession.preview()
        await session.activate(repository: repository)
        let readinessTracker = DocumentationScreenshotReadinessTracker()
        session.store.catalogLookupClient = trackedCatalogClient(
            repository: repository,
            readinessTracker: readinessTracker
        )

        let resolved = seeded.tracks.map {
            ResolvedPlaybackTrack(
                track: LibraryProjectionFactory.playback($0),
                mediaURL: URL(filePath: "/tmp/\($0.id).flac")
            )
        }
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: resolved),
            backends: [PlaybackTestBackend(kind: .pcm)]
        )
        let model = CadenceAppModel(
            runtimeEnvironment: .preview(
                CadencePreviewFixture(
                    importCandidates: .mockImportCandidates
                )
            ),
            importRuntimeAvailability: .preview,
            librarySession: session,
            playbackCoordinator: coordinator
        )
        let trackIDs = resolved.map(\.track.id)
        await coordinator.startQueue(
            source: .album(seeded.albumID),
            trackIDs: trackIDs,
            startingAt: session.store.recentlyPlayedTracks.first?.id
        )
        coordinator.receive(.time(89), from: .pcm)
        coordinator.pause()

        return DocumentationScreenshotFixture(
            model: model,
            albumID: seeded.albumID,
            artistID: seeded.artistID,
            tagID: seeded.tagID,
            readinessTracker: readinessTracker
        )
    }

    static func makeEmpty() async throws -> DocumentationScreenshotFixture {
        let container = try LibraryContainerFactory.inMemory()
        let repository = LibraryRepository(modelContainer: container)
        let session = LibrarySession.preview()
        await session.activate(repository: repository)
        let readinessTracker = DocumentationScreenshotReadinessTracker()
        let model = CadenceAppModel(
            runtimeEnvironment: .preview(CadencePreviewFixture()),
            importRuntimeAvailability: .preview,
            librarySession: session,
            playbackCoordinator: makePlaybackCoordinator(
                resolver: PlaybackTestResolver(tracks: []),
                backends: [PlaybackTestBackend(kind: .pcm)]
            )
        )
        return DocumentationScreenshotFixture(
            model: model,
            albumID: UUID(),
            artistID: UUID(),
            tagID: UUID(),
            readinessTracker: readinessTracker
        )
    }

    func capture(
        _ filename: String,
        contentSize: NSSize = .minimum,
        appearance: DocumentationScreenshotAppearance = .dark,
        rhythmPulseVisualQAState: RhythmPulseVisualQAState? = nil
    ) async throws {
        try await capture(
            filename,
            rootView: CadenceRootView(model: model),
            contentSize: contentSize,
            appearance: appearance,
            scene: inferredScene,
            rhythmPulseVisualQAState: rhythmPulseVisualQAState
        )
    }

    func captureSettings(
        _ filename: String,
        contentSize: NSSize = .settings,
        appearance: DocumentationScreenshotAppearance = .dark,
        tab: CadenceSettingsTab = .general
    ) async throws {
        try await capture(
            filename,
            rootView: CadenceSettingsWindow(
                model: model,
                updateController: CadenceUpdateController(
                    startsUpdater: false
                ),
                selection: tab
            ),
            contentSize: contentSize,
            appearance: appearance,
            scene: .settings(tab)
        )
    }

    func waitUntilReady(
        for scene: DocumentationScreenshotScene,
        timeout: Duration = .seconds(3)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !isReady(for: scene) {
            guard clock.now < deadline else {
                throw DocumentationScreenshotReadinessError.timedOut(
                    scene,
                    diagnostic: readinessDiagnostic(for: scene)
                )
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func capture(
        _ filename: String,
        rootView: some View,
        contentSize: NSSize,
        appearance: DocumentationScreenshotAppearance,
        scene: DocumentationScreenshotScene,
        rhythmPulseVisualQAState: RhythmPulseVisualQAState? = nil
    ) async throws {
        readinessTracker.prepareForCapture(scene)
        let rootView = rootView
            .frame(width: contentSize.width, height: contentSize.height)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .environment(
                \.rhythmPulseVisualQAState,
                rhythmPulseVisualQAState
            )
            .environment(
                \.albumDetailReadinessObserver,
                AlbumDetailReadinessObserver(
                    notify: readinessTracker.didRenderAlbum
                )
            )
            .environment(
                \.visualRegressionUsesStableSystemControls,
                true
            )
            .tint(CadenceTheme.primaryAccent)

        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Cadence"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: appearance.appKitName)
        window.contentView = hostingView
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        window.setContentSize(contentSize)
        window.makeKeyAndOrderFront(nil)

        // Mount the SwiftUI tree before waiting for view-owned async tasks.
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        try await waitUntilReady(for: scene)
        hostingView.layoutSubtreeIfNeeded()
        await Task.yield()
        let data = try pngData(for: window)
        try Self.storeScreenshot(
            data,
            filename: filename
        )
        window.close()
    }

    private func pngData(
        for window: NSWindow
    ) throws -> Data {
        guard
            let frameView = window.contentView?.superview,
            let representation = frameView.bitmapImageRepForCachingDisplay(
                in: frameView.bounds
            )
        else {
            throw DocumentationScreenshotError.captureUnavailable
        }
        frameView.cacheDisplay(in: frameView.bounds, to: representation)
        guard let data = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw DocumentationScreenshotError.encodingFailed
        }
        return data
    }

    private static var projectRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
enum DocumentationScreenshotAppearance: CaseIterable {
    case system
    case dark
    case light

    var appKitName: NSAppearance.Name {
        switch self {
        case .system: NSApp.effectiveAppearance.name
        case .dark: .darkAqua
        case .light: .aqua
        }
    }

    var slug: String {
        switch self {
        case .system: "system"
        case .dark: "dark"
        case .light: "light"
        }
    }
}

enum DocumentationScreenshotViewport: CaseIterable {
    case minimum
    case ideal
    case wide

    var size: NSSize {
        switch self {
        case .minimum: .minimum
        case .ideal: .ideal
        case .wide: .wide
        }
    }

    var slug: String {
        switch self {
        case .minimum: "min"
        case .ideal: "ideal"
        case .wide: "wide"
        }
    }
}

extension NSSize {
    static let minimum = NSSize(width: 1080, height: 844)
    static let ideal = NSSize(width: 1512, height: 982)
    static let wide = NSSize(width: 1440, height: 868)
    static let large = NSSize(width: 2200, height: 1300)
    static let settings = NSSize(width: 760, height: 640)
}

@MainActor
private extension DocumentationScreenshotFixture {
    var inferredScene: DocumentationScreenshotScene {
        if model.playbackWorkspace == .nowPlaying {
            return .nowPlaying
        }
        if model.selectedDestination == .albums,
           let albumID = model.selectedProductionAlbumID {
            return .album(albumID)
        }
        switch model.selectedDestination {
        case .home:
            return .home
        case .importMusic:
            return .importReview
        default:
            return .library(model.selectedDestination)
        }
    }

    func isReady(for scene: DocumentationScreenshotScene) -> Bool {
        guard model.librarySession.availability == .ready else {
            return false
        }
        switch scene {
        case .home:
            return model.selectedDestination == .home
        case let .library(destination):
            let destinationIsReady = if destination == .allTracks {
                model.librarySession.store.allTracksWindow?.firstPageState
                    == .ready
            } else {
                true
            }
            return model.playbackWorkspace == .hidden
                && model.selectedDestination == destination
                && destinationIsReady
        case let .album(albumID):
            return model.selectedProductionAlbumID == albumID
                && readinessTracker.isAlbumReady(albumID)
        case .nowPlaying:
            return model.playbackWorkspace == .nowPlaying
                && model.currentPlaybackTrack != nil
        case .importReview:
            return model.selectedDestination == .importMusic
                && model.importPreviewStage == .review
                && !model.importCandidates.isEmpty
        case .settings:
            return true
        }
    }

    func readinessDiagnostic(
        for scene: DocumentationScreenshotScene
    ) -> String {
        switch scene {
        case .home:
            "destination=\(model.selectedDestination)"
        case let .album(albumID):
            "selected=\(String(describing: model.selectedProductionAlbumID)), "
                + readinessTracker.albumDiagnostic(albumID)
        case .library(.allTracks):
            "destination=\(model.selectedDestination), firstPage="
                + "\(String(describing: model.librarySession.store.allTracksWindow?.firstPageState))"
        default:
            "destination=\(model.selectedDestination), workspace=\(model.playbackWorkspace)"
        }
    }

    static func trackedCatalogClient(
        repository: LibraryRepository,
        readinessTracker: DocumentationScreenshotReadinessTracker
    ) -> LibraryCatalogLookupClient {
        let base = LibraryCatalogLookupClient(repository: repository)
        return LibraryCatalogLookupClient(
            artist: base.artist,
            album: { id in
                let album = try await base.album(id)
                await readinessTracker.didLoadAlbum(id)
                return album
            },
            albumTracks: { id in
                let tracks = try await base.albumTracks(id)
                await readinessTracker.didLoadAlbumTracks(id)
                return tracks
            },
            artistTracks: base.artistTracks,
            artistAlbums: base.artistAlbums,
            artistReleases: base.artistReleases,
            tagTracks: base.tagTracks,
            allTrackIDs: base.allTrackIDs
        )
    }

    func captureMatrix(prefix: String) async throws {
        for viewport in DocumentationScreenshotViewport.allCases {
            for appearance in DocumentationScreenshotAppearance.allCases {
                try await capture(
                    "qa-\(prefix)-\(viewport.slug)-\(appearance.slug).png",
                    contentSize: viewport.size,
                    appearance: appearance
                )
            }
        }
    }

    func captureSettingsMatrix() async throws {
        for tab in CadenceSettingsTab.allCases {
            for appearance in DocumentationScreenshotAppearance.allCases {
                try await captureSettings(
                    "qa-settings-\(tab.rawValue)-\(appearance.slug).png",
                    appearance: appearance,
                    tab: tab
                )
            }
        }
    }

    static func storeScreenshot(
        _ data: Data,
        filename: String
    ) throws {
        let baseline = projectRoot.appending(path: "docs/images/\(filename)")
        let workspace = FileManager.default.temporaryDirectory.appending(
            path: "CadenceVisualRegression",
            directoryHint: .isDirectory
        )
        let marker = projectRoot.appending(path: ".build/update-screenshots")
        if FileManager.default.fileExists(atPath: marker.path) {
            try data.write(to: baseline, options: .atomic)
            return
        }

        let actual = workspace.appending(path: "actual/\(filename)")
        let diff = workspace.appending(path: "diff/\(filename)")
        try FileManager.default.createDirectory(
            at: actual.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: actual, options: .atomic)
        try DocumentationScreenshotComparator.assertMatch(
            actual: actual,
            baseline: baseline,
            diff: diff
        )
    }
}

private extension DocumentationScreenshotFixture {
    struct SeededLibrary {
        let tracks: [TrackRecord]
        let albumID: UUID
        let artistID: UUID
        let tagID: UUID
    }

    func installLongLocalizedHomeMetadata() {
        let store = model.librarySession.store
        let recentTracks = store.recentlyPlayedTracks.enumerated()
        store.recentlyPlayedTracks = recentTracks.map { index, track in
            track.replacingHomeMetadata(
                title: index.isMultiple(of: 2)
                    ? "Сигналы, которые остаются после полуночи"
                    : "Путешествие сквозь очень тихий зимний город",
                artist: "Северный экспериментальный ансамбль"
            )
        }
        let favoriteTracks = store.favoriteTracks.enumerated()
        store.favoriteTracks = favoriteTracks.map { index, track in
            track.replacingHomeMetadata(
                title: index.isMultiple(of: 2)
                    ? "Архитектура исчезающего света"
                    : "Возвращение к дальним спутникам",
                artist: "Оркестр стеклянного района"
            )
        }
    }

    static func seed(
        _ container: ModelContainer
    ) throws -> SeededLibrary {
        let context = ModelContext(container)
        let importID = UUID()
        let artists = makeArtists()
        let albums = makeAlbums(artists: artists)
        let tracks = makeTracks(albums: albums, importID: importID)
        let tag = TagRecord(
            displayPath: "context/late night",
            groupPath: "context"
        )
        let ambientTag = TagRecord(
            displayPath: "genre/ambient",
            groupPath: "genre"
        )
        persist(
            artists: artists,
            albums: albums,
            tracks: tracks,
            tags: [tag, ambientTag],
            context: context
        )
        try context.save()

        return SeededLibrary(
            tracks: tracks,
            albumID: albums[0].id,
            artistID: artists[0].id,
            tagID: tag.id
        )
    }

    static func makeTracks(
        albums: [AlbumRecord],
        importID: UUID
    ) -> [TrackRecord] {
        trackTitles.enumerated().map { index, title in
            let album = albums[index / 3]
            return TrackRecord(
                originalFilename: "synthetic-\(index).flac",
                title: title,
                duration: 210 + Double(index * 9),
                codec: "FLAC",
                container: "flac",
                sampleRate: 96000,
                channelCount: 2,
                bitDepth: 24,
                contentHash: String(format: "%064x", index + 1),
                relativeMediaPath: "Media/synthetic-\(index).flac",
                importSessionID: importID,
                artist: album.artist,
                album: album,
                trackNumber: index % 3 + 1,
                lastPlayedAt: index < 7
                    ? Date(timeIntervalSince1970: 1_800_000_000 - Double(index))
                    : nil,
                isFavorite: index < 4,
                spatialFormat: .stereo
            )
        }
    }

    static func persist(
        artists: [ArtistRecord],
        albums: [AlbumRecord],
        tracks: [TrackRecord],
        tags: [TagRecord],
        context: ModelContext
    ) {
        artists.forEach(context.insert)
        albums.forEach(context.insert)
        tracks.forEach(context.insert)
        tags.forEach(context.insert)
        for item in tracks.prefix(7) {
            context.insert(
                TagAssignmentRecord(
                    targetKind: .track,
                    targetID: item.id,
                    tagID: tags[0].id
                )
            )
        }
    }

    static let trackTitles = [
        "Midnight Static",
        "Glass Horizon",
        "Transmission Lines",
        "Fade in the Distance",
        "Hollow Frequency",
        "Afterimage",
        "Distant Satellites",
        "Static Bloom",
        "Quiet Return",
        "Night Windows",
        "Falling Signals",
        "Approaching Light",
    ]

    static func makeArtists() -> [ArtistRecord] {
        [
            ArtistRecord(
                name: "North Assembly",
                isFavorite: true,
                favoriteDate: Date(timeIntervalSince1970: 1_800_000_000),
                trackCount: 6,
                albumCount: 2
            ),
            ArtistRecord(name: "Glass District", trackCount: 3, albumCount: 1),
            ArtistRecord(name: "Mara Vale", trackCount: 3, albumCount: 1),
        ]
    }

    static func makeAlbums(
        artists: [ArtistRecord]
    ) -> [AlbumRecord] {
        [
            AlbumRecord(
                title: "Signals After Dark",
                artist: artists[0],
                year: 2026,
                isFavorite: true,
                favoriteDate: Date(timeIntervalSince1970: 1_800_000_000),
                trackCount: 3,
                totalDuration: 657
            ),
            AlbumRecord(
                title: "Coastal Machines",
                artist: artists[0],
                year: 2025,
                trackCount: 3,
                totalDuration: 738
            ),
            AlbumRecord(
                title: "Glass Horizon",
                artist: artists[1],
                year: 2024,
                trackCount: 3,
                totalDuration: 819
            ),
            AlbumRecord(
                title: "Transient Lines",
                artist: artists[2],
                year: 2026,
                trackCount: 3,
                totalDuration: 900
            ),
        ]
    }
}

private extension LibraryTrackProjection {
    func replacingHomeMetadata(
        title: String,
        artist: String
    ) -> LibraryTrackProjection {
        LibraryTrackProjection(
            id: id,
            title: title,
            artistID: artistID,
            artist: artist,
            albumID: albumID,
            album: album,
            duration: duration,
            year: year,
            codec: codec,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitDepth: bitDepth,
            isFavorite: isFavorite,
            isExplicit: isExplicit,
            customArtworkID: customArtworkID,
            artworkID: artworkID,
            relativeMediaPath: relativeMediaPath,
            lastPlayedAt: lastPlayedAt,
            hasSynchronizedLyrics: hasSynchronizedLyrics
        )
    }
}

private final class HomeScreenshotPreferences {
    private let defaults = UserDefaults.standard
    private let values: [String: [String]]
    private let previousValues: [String: Any]

    init(fixture: DocumentationScreenshotFixture) {
        let values = [
            HomePinKind.album.storageKey: [fixture.albumID.uuidString],
            HomePinKind.artist.storageKey: [fixture.artistID.uuidString],
        ]
        let defaults = UserDefaults.standard
        self.values = values
        previousValues = values.keys.reduce(into: [:]) { result, key in
            result[key] = defaults.object(forKey: key)
        }
    }

    func install() {
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        defaults.set(
            defaults.integer(forKey: "home.pins.revision") + 1,
            forKey: "home.pins.revision"
        )
    }

    func restore() {
        for key in values.keys {
            if let value = previousValues[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

/// Isolates captures from navigation preferences mutated by other test suites.
private final class NavigationScreenshotPreferences {
    private let defaults = UserDefaults.standard
    private let values: [String: Any] = [
        "navigationRail.expanded": true,
        "navigationRail.order": NavigationRailConfiguration.defaultOrderRawValue,
        "navigationRail.hidden": "",
        "trackTable.visibleColumns": TrackTableColumn.defaultRawValue,
        "trackTable.columnDefaultsVersion": 2,
        "trackTable.sortField": TrackTableSortField.song.rawValue,
        "trackTable.sortDirection": TrackTableSortDirection.ascending.rawValue,
        "trackTable.songWidth": TrackTableWidth.song.defaultValue,
        "trackTable.albumWidth": TrackTableWidth.album.defaultValue,
        "trackTable.yearWidth": TrackTableWidth.year.defaultValue,
        "trackTable.timeWidth": TrackTableWidth.time.defaultValue,
        "tags.sidebarWidth": 300.0,
        "tags.inspectorWidth": 330.0,
    ]
    private let previousValues: [String: Any]

    init() {
        let keys = [
            "navigationRail.expanded",
            "navigationRail.order",
            "navigationRail.hidden",
            "trackTable.visibleColumns",
            "trackTable.columnDefaultsVersion",
            "trackTable.sortField",
            "trackTable.sortDirection",
            "trackTable.songWidth",
            "trackTable.albumWidth",
            "trackTable.yearWidth",
            "trackTable.timeWidth",
            "tags.sidebarWidth",
            "tags.inspectorWidth",
        ]
        previousValues = keys.reduce(into: [:]) { result, key in
            result[key] = UserDefaults.standard.object(forKey: key)
        }
    }

    func install() {
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
    }

    func restore() {
        for key in values.keys {
            if let value = previousValues[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

private enum DocumentationScreenshotError: Error {
    case captureUnavailable
    case encodingFailed
}
