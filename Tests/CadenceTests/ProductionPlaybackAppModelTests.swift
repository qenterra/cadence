@testable import Cadence
import Foundation
import SwiftData
import Testing

@MainActor
struct ProductionPlaybackAppModelTests {
    @Test("Lyrics editor clock uses presentation time rather than progress")
    func lyricsEditorClockUsesPresentationClock() {
        let presentation = LyricsEditorClockPresentation.resolve(
            stateTime: 51,
            presentationTime: 51.792,
            isPlaying: true
        )

        #expect(presentation == "0:51.792")
    }

    @Test("Repeat control mutates the production coordinator")
    func productionRepeatControl() {
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: []),
            backends: [PlaybackTestBackend(kind: .pcm)]
        )
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .unavailable("Not used by this test."),
            librarySession: .preview(),
            playbackCoordinator: coordinator
        )

        model.cycleRepeatMode()

        #expect(coordinator.repeatMode == .all)
        #expect(model.repeatMode == .all)
    }

    @Test("Mute restores the last audible volume")
    func muteToggleRestoresVolume() {
        let model = CadenceAppModel.testFixture()
        model.volume = 0.42

        model.toggleMute()
        #expect(model.volume == 0)

        model.toggleMute()
        #expect(model.volume == 0.42)
    }

    @Test("Production app state reflects the real coordinator")
    func stateBridge() async {
        let resolved = [
            playbackTestTrack(id: UUID(), title: "One"),
            playbackTestTrack(id: UUID(), title: "Two"),
        ]
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: resolved),
            backends: [PlaybackTestBackend(kind: .pcm)]
        )
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .unavailable("Not used by this test."),
            librarySession: .preview(),
            playbackCoordinator: coordinator
        )

        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: resolved.map(\.track.id)
        )

        #expect(model.currentPlaybackTrack?.id == resolved[0].track.id)
        #expect(model.isPlaying)
        #expect(model.progress == 0)

        coordinator.receive(.time(30), from: .pcm)
        #expect(model.playbackCurrentTime == 30)
        #expect(
            model.progress
                == 30 / resolved[0].track.duration
        )
    }

    @Test("Committed production seek keeps the requested progress")
    func committedSeek() async {
        let resolved = playbackTestTrack(
            id: UUID(),
            title: "Seek",
            duration: 200
        )
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [resolved]),
            backends: [backend]
        )
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .unavailable("Not used by this test."),
            librarySession: .preview(),
            playbackCoordinator: coordinator
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [resolved.track.id]
        )

        await model.seekPlayback(toProgress: 0.4)

        #expect(backend.seekTimes == [80])
        #expect(model.playbackCurrentTime == 80)
        #expect(model.progress == 0.4)
    }

    @Test("Production queue edits support Undo and Redo in Up Next only")
    func productionQueueUndoRedo() async {
        let resolved = (0 ..< 5).map {
            playbackTestTrack(id: UUID(), title: "Track \($0)")
        }
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: resolved),
            backends: [PlaybackTestBackend(kind: .pcm)]
        )
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .unavailable("Not used by this test."),
            librarySession: .preview(),
            playbackCoordinator: coordinator
        )
        let ids = resolved.map(\.track.id)
        let expectedAfterRemoval = [ids[0], ids[1], ids[2], ids[4]]
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: ids,
            startingAt: ids[1]
        )
        coordinator.receive(.time(23), from: .pcm)
        let undoManager = UndoManager()

        #expect(
            model.removeFromProductionQueue(
                [ids[0], ids[1], ids[3]],
                undoManager: undoManager
            )
        )
        #expect(coordinator.state.queue?.orderedTrackIDs == expectedAfterRemoval)
        #expect(coordinator.state.currentTime == 23)

        undoManager.undo()
        #expect(coordinator.state.queue?.orderedTrackIDs == ids)
        #expect(coordinator.state.queue?.currentTrackID == ids[1])
        #expect(coordinator.state.currentTime == 23)

        undoManager.redo()
        #expect(coordinator.state.queue?.orderedTrackIDs == expectedAfterRemoval)
        #expect(coordinator.state.currentTrack?.id == ids[1])
        #expect(coordinator.state.currentTime == 23)
    }

    @Test("Production Lyrics Editor saves the exact playback UUID")
    func productionLyricsEditorSaves() async throws {
        let fixture = try ProductionLyricsFixture(registerTrack: true)
        defer { fixture.remove() }
        await fixture.startPlayback()

        #expect(fixture.model.presentLyricsEditor())
        for _ in 0 ..< 100 where fixture.model.isLoadingLyricDraft {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(
            fixture.model.lyricDraft?.trackID
                == .managed(fixture.trackID)
        )
        let lineID = try #require(
            fixture.model.lyricDraft?.lines.first?.id
        )
        fixture.model.updateLyricText(
            lineID: lineID,
            text: "Managed lyric"
        )

        #expect(await fixture.model.saveLyricDraftPersisting())

        #expect(!fixture.model.isLyricDraftDirty)
        #expect(fixture.model.lyricsRevision == 1)
        #expect(
            try String(
                contentsOf: fixture.package.lyricURL(
                    trackID: fixture.trackID
                ),
                encoding: .utf8
            ) == "Managed lyric\n"
        )
        #expect(
            try await fixture.model.loadProductionLyrics(
                for: #require(
                    fixture.model.currentPlaybackTrack
                )
            )?.lines.map(\.text) == ["Managed lyric"]
        )
    }

    @Test("Production save failure keeps the draft dirty")
    func productionLyricsFailurePreservesDraft() async throws {
        let fixture = try ProductionLyricsFixture(registerTrack: false)
        defer { fixture.remove() }
        await fixture.startPlayback()
        #expect(fixture.model.presentLyricsEditor())
        for _ in 0 ..< 100 where fixture.model.isLoadingLyricDraft {
            try await Task.sleep(for: .milliseconds(10))
        }
        let lineID = try #require(
            fixture.model.lyricDraft?.lines.first?.id
        )
        fixture.model.updateLyricText(
            lineID: lineID,
            text: "Do not lose this"
        )

        #expect(await !(fixture.model.saveLyricDraftPersisting()))

        #expect(fixture.model.isLyricDraftDirty)
        #expect(fixture.model.lyricPersistenceError != nil)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.package.lyricURL(
                    trackID: fixture.trackID
                ).path
            )
        )
    }
}

@MainActor
private struct ProductionLyricsFixture {
    let rootURL: URL
    let package: ManagedLibraryPackage
    let trackID: UUID
    let coordinator: PlaybackCoordinator
    let model: CadenceAppModel

    init(registerTrack: Bool) throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "CadenceProductionLyrics-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let musicURL = rootURL.appending(
            path: "Music",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: musicURL,
            withIntermediateDirectories: true
        )
        package = ManagedLibraryPackage(
            location: ManagedLibraryLocation(musicDirectory: musicURL)
        )
        try package.bootstrapForConfirmedImport()
        try package.writeIdentity(LibraryIdentity())
        trackID = UUID()

        let container = try LibraryContainerFactory.persistent(
            package: package
        )
        try Self.registerTrack(
            id: trackID,
            in: container,
            when: registerTrack
        )
        let session = LibrarySession.startup(
            location: package.location
        )
        let resolved = playbackTestTrack(
            id: trackID,
            title: "Track"
        )
        coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [resolved]),
            backends: [PlaybackTestBackend(kind: .pcm)]
        )
        model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .unavailable("Not used by this test."),
            librarySession: session,
            playbackCoordinator: coordinator
        )
    }

    private static func registerTrack(
        id: UUID,
        in container: ModelContainer,
        when shouldRegister: Bool
    ) throws {
        guard shouldRegister else {
            return
        }
        let context = ModelContext(container)
        context.insert(
            TrackRecord(
                id: id,
                originalFilename: "Track.flac",
                title: "Track",
                duration: 120,
                codec: "FLAC",
                container: "FLAC",
                sampleRate: 48000,
                channelCount: 2,
                bitDepth: 24,
                contentHash: String(repeating: "b", count: 64),
                relativeMediaPath: "Media/\(id.uuidString).flac",
                importSessionID: UUID()
            )
        )
        try context.save()
    }

    func startPlayback() async {
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [trackID]
        )
    }

    func remove() {
        model.shutdownPlayback()
        try? FileManager.default.removeItem(at: rootURL)
    }
}
