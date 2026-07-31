import AVFoundation
@testable import Cadence
import Foundation
import Testing

@MainActor
struct CadenceAppModelFactoryTests {
    @Test("Production starts empty without creating Cadence.library")
    func productionStartsEmpty() throws {
        try withTemporaryDirectory { musicDirectory in
            let location = ManagedLibraryLocation(
                musicDirectory: musicDirectory
            )
            let session = LibrarySession.startup(location: location)
            let model = CadenceAppModel.production(
                librarySession: session
            )

            #expect(model.tracks.isEmpty)
            #expect(model.tags.isEmpty)
            #expect(model.smartCollections.isEmpty)
            #expect(model.lyricDocuments.isEmpty)
            #expect(model.favoriteAlbumDates.isEmpty)
            #expect(model.favoriteArtistDates.isEmpty)
            #expect(model.importCandidates.isEmpty)
            #expect(model.importCoordinator != nil)
            #expect(!model.isImportPreviewMode)
            #expect(model.librarySession.availability == .empty)
            #expect(
                !FileManager.default.fileExists(
                    atPath: location.packageURL.path
                )
            )
        }
    }

    @Test("Preview keeps explicit visual fixtures")
    func previewKeepsFixtures() {
        let model = CadenceAppModel.testFixture()

        #expect(!model.tracks.isEmpty)
        #expect(!model.tags.isEmpty)
        #expect(!model.smartCollections.isEmpty)
        #expect(!model.importCandidates.isEmpty)
        #expect(model.importCoordinator == nil)
        #expect(model.isImportPreviewMode)
        #expect(model.librarySession.availability == .preview)
    }

    @Test("Preview defaults are honest and empty")
    func previewDefaultsAreEmpty() {
        let model = CadenceAppModel.preview()

        #expect(model.tracks.isEmpty)
        #expect(model.tags.isEmpty)
        #expect(model.smartCollections.isEmpty)
        #expect(model.lyricDocuments.isEmpty)
        #expect(model.favoriteAlbumDates.isEmpty)
        #expect(model.favoriteArtistDates.isEmpty)
        #expect(model.importCandidates.isEmpty)
    }

    @Test("A damaged existing package blocks startup without replacement")
    func damagedPackageBlocksStartup() throws {
        try withTemporaryDirectory { musicDirectory in
            let location = ManagedLibraryLocation(
                musicDirectory: musicDirectory
            )
            try Data("not a package".utf8).write(
                to: location.packageURL
            )

            let session = LibrarySession.startup(location: location)

            guard case .failed = session.availability else {
                Issue.record("Expected a blocking startup failure.")
                return
            }
            #expect(
                try Data(contentsOf: location.packageURL)
                    == Data("not a package".utf8)
            )
        }
    }

    @Test("Production Scan reaches Review without creating Cadence.library")
    func productionScanIsReadOnly() async throws {
        let musicDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "Cadence-Music-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "Cadence-Source-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: musicDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: musicDirectory)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        try writeSilentWAV(
            to: sourceDirectory.appending(path: "Review Me.wav")
        )

        let location = ManagedLibraryLocation(
            musicDirectory: musicDirectory
        )
        let model = CadenceAppModel.production(
            librarySession: .startup(location: location)
        )
        model.acceptImportDrop(urls: [sourceDirectory])

        for _ in 0 ..< 200 where model.importPreviewStage != .review {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.importPreviewStage == .review)
        #expect(model.importCandidates.count == 1)
        #expect(model.importCandidates.first?.title == "Review Me")
        #expect(
            !FileManager.default.fileExists(
                atPath: location.packageURL.path
            )
        )
        model.importCoordinator?.cancel()
    }

    @Test("Production Review commits files and publishes Complete")
    func productionImportCompletes() async throws {
        let directories = try makeImportDirectories()
        let musicDirectory = directories.music
        let sourceDirectory = directories.source
        defer {
            try? FileManager.default.removeItem(at: musicDirectory)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let sourceAudio = sourceDirectory.appending(
            path: "Commit Me.wav"
        )
        try writeSilentWAV(to: sourceAudio)

        let location = ManagedLibraryLocation(
            musicDirectory: musicDirectory
        )
        let model = CadenceAppModel.production(
            librarySession: .startup(location: location)
        )
        model.acceptImportDrop(urls: [sourceDirectory])
        for _ in 0 ..< 300 where model.importPreviewStage != .review {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.importPreviewStage == .review)

        model.beginImportPreview()
        for _ in 0 ..< 500 where model.importPreviewStage != .complete {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.importPreviewStage == .complete)
        #expect(model.managedImportCompletion?.importedTrackIDs.count == 1)
        #expect(FileManager.default.fileExists(atPath: sourceAudio.path))
        #expect(
            FileManager.default.fileExists(
                atPath: location.packageURL.path
            )
        )
        for _ in 0 ..< 200 where model.librarySession.availability != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.librarySession.availability == .ready)
        #expect(model.librarySession.store.tracks.map(\.title) == ["Commit Me"])
        try await assertImportedTrackCanLoad(in: model)
    }

    private func assertImportedTrackCanLoad(
        in model: CadenceAppModel
    ) async throws {
        let importedTrackID = try #require(
            model.librarySession.store.tracks.first?.id
        )
        let resolved = try await ManagedPlaybackTrackResolver(
            librarySession: model.librarySession
        ).resolve(trackIDs: [importedTrackID])
        let playbackTrack = try #require(resolved.first)
        let backend = PCMPlaybackBackend()
        try await backend.load(
            PlaybackBackendLoadRequest(
                current: playbackTrack,
                next: nil,
                startTime: 0,
                autoplay: false,
                volume: 1,
                replayGainDecibels: nil
            )
        )
        #expect(backend.currentItem?.resolved.track.id == importedTrackID)
        backend.stop()
    }

    private func makeImportDirectories() throws -> (
        music: URL,
        source: URL
    ) {
        let root = FileManager.default.temporaryDirectory
        let music = root.appending(
            path: "Cadence-Import-Music-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let source = root.appending(
            path: "Cadence-Import-Source-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: music,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        return (music, source)
    }

    private func withTemporaryDirectory(
        _ operation: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "CadenceFactoryTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try operation(directory)
    }

    private func writeSilentWAV(
        to url: URL
    ) throws {
        let format = try #require(
            AVAudioFormat(
                standardFormatWithSampleRate: 44100,
                channels: 2
            )
        )
        let frameCount: AVAudioFrameCount = 441
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            )
        )
        buffer.frameLength = frameCount

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings
        )
        try file.write(from: buffer)
    }
}
