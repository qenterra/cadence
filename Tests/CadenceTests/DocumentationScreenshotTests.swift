import AppKit
@testable import Cadence
import SwiftData
import SwiftUI
import Testing

@MainActor
struct DocumentationScreenshotTests {
    @Test("Render public screenshots from production projections")
    func renderProductionScreenshots() async throws {
        guard FileManager.default.fileExists(atPath: Self.updateMarker.path) else {
            return
        }

        let fixture = try await DocumentationScreenshotFixture.make()

        fixture.model.selectedDestination = .library
        try await fixture.capture("cadence-library.png")

        fixture.model.presentNowPlaying()
        fixture.model.selectedNowPlayingPanel = .queue
        try await fixture.capture("cadence-now-playing.png")

        fixture.model.dismissNowPlaying()
        fixture.model.selectedDestination = .tags
        fixture.model.selectedProductionTagID = fixture.tagID
        try await fixture.capture("cadence-tags.png")

        fixture.model.selectedDestination = .settings
        try await fixture.capture("cadence-settings.png")
    }

    private static var updateMarker: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build/update-screenshots")
    }
}

@MainActor
private final class DocumentationScreenshotFixture {
    let model: CadenceAppModel
    let tagID: UUID
    private let guideCoordinator: GuideCoordinator

    init(
        model: CadenceAppModel,
        tagID: UUID
    ) {
        self.model = model
        self.tagID = tagID
        guideCoordinator = GuideCoordinator(
            progressStore: InMemoryGuideProgressStore(
                completedOnboardingVersion: GuideCatalog.onboardingVersion
            )
        )
    }

    static func make() async throws -> DocumentationScreenshotFixture {
        let container = try LibraryContainerFactory.inMemory()
        let seeded = try seed(container)
        let repository = LibraryRepository(modelContainer: container)
        let session = LibrarySession.preview()
        await session.activate(repository: repository)

        let resolved = seeded.tracks.map {
            ResolvedPlaybackTrack(
                track: LibraryProjectionFactory.playback($0),
                mediaURL: URL(filePath: "/tmp/\($0.id).flac")
            )
        }
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: resolved),
            backends: [PlaybackTestBackend(kind: .pcm)]
        )
        let model = CadenceAppModel(
            librarySession: session,
            tracks: [],
            tags: [],
            tagAssignments: [],
            tagExclusions: [],
            smartCollections: [],
            lyricDocuments: [:],
            favoriteAlbumDates: [:],
            favoriteArtistDates: [:],
            importCandidates: [],
            playbackCoordinator: coordinator
        )
        let trackIDs = resolved.map(\.track.id)
        await coordinator.startQueue(
            source: .album(seeded.albumID),
            trackIDs: trackIDs,
            startingAt: trackIDs.first
        )
        coordinator.receive(.time(89), from: .pcm)

        return DocumentationScreenshotFixture(
            model: model,
            tagID: seeded.tagID
        )
    }

    func capture(
        _ filename: String
    ) async throws {
        let contentSize = NSSize(width: 1080, height: 836)
        let rootView = CadenceRootView(
            model: model,
            guideCoordinator: guideCoordinator
        )
        .frame(width: contentSize.width, height: contentSize.height)
        .environment(\.colorScheme, .dark)

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
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)

        try await Task.sleep(for: .milliseconds(500))
        hostingView.layoutSubtreeIfNeeded()
        try pngData(for: window).write(
            to: Self.outputDirectory.appending(path: filename),
            options: .atomic
        )
        window.orderOut(nil)
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

    private static var outputDirectory: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/images", directoryHint: .isDirectory)
    }
}

private extension DocumentationScreenshotFixture {
    struct SeededLibrary {
        let tracks: [TrackRecord]
        let albumID: UUID
        let tagID: UUID
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
                dateAdded: Date(timeIntervalSince1970: 1_760_000_000)
                    .addingTimeInterval(Double(index * 60)),
                playCount: 24 - index,
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
            ArtistRecord(name: "North Assembly", trackCount: 6, albumCount: 2),
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

private enum DocumentationScreenshotError: Error {
    case captureUnavailable
    case encodingFailed
}
