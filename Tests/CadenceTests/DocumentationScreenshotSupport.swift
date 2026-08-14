import AppKit
@testable import Cadence
import Foundation
import SwiftData
import SwiftUI
import Testing

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

    static var projectRoot: URL {
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
