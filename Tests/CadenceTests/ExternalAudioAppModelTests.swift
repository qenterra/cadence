@testable import Cadence
import Foundation
import Testing

@MainActor
struct ExternalAudioAppModelTests {
    @Test("Opening files starts one ordered memory-only queue")
    func orderedAutoplay() async throws {
        let files = try ExternalAppModelFiles(names: ["One.flac", "Two.mp3"])
        defer { files.remove() }
        let harness = externalModelHarness(
            metadataByURL: [
                files.urls[0]: appModelMetadata(title: "One"),
                files.urls[1]: appModelMetadata(title: "Two"),
            ]
        )

        await harness.model.openExternalAudio(urls: files.urls)

        let queue = try #require(harness.coordinator.state.queue)
        #expect(queue.source == .externalFiles)
        #expect(queue.orderedTrackIDs.count == 2)
        #expect(harness.model.currentExternalAudioItem?.sourceURL == files.urls[0])
        #expect(harness.coordinator.state.currentTrack?.title == "One")
        #expect(harness.coordinator.state.isPlaying)
        #expect(
            harness.model.productionPlaybackQueueTracks.compactMap {
                $0.track?.title
            }
                == ["One", "Two"]
        )
        #expect(harness.model.librarySession.location == nil)
        #expect(harness.model.librarySession.store.catalogCounts == .empty)
    }

    @Test("A valid later request replaces the queue while invalid input does not")
    func replacementIsFailClosed() async throws {
        let files = try ExternalAppModelFiles(
            names: ["One.flac", "Two.mp3", "Unsupported.txt"]
        )
        defer { files.remove() }
        let harness = externalModelHarness(
            metadataByURL: [
                files.urls[0]: appModelMetadata(title: "One"),
                files.urls[1]: appModelMetadata(title: "Two"),
            ]
        )

        await harness.model.openExternalAudio(urls: [files.urls[0]])
        let firstIDs = try #require(
            harness.coordinator.state.queue?.orderedTrackIDs
        )
        await harness.model.openExternalAudio(urls: [files.urls[2]])
        #expect(harness.coordinator.state.queue?.orderedTrackIDs == firstIDs)
        #expect(harness.model.externalAudioOpenError != nil)

        await harness.model.openExternalAudio(urls: [files.urls[1]])
        #expect(harness.coordinator.state.queue?.orderedTrackIDs != firstIDs)
        #expect(harness.model.currentExternalAudioItem?.sourceURL == files.urls[1])
        #expect(harness.model.externalAudioOpenError == nil)
    }

    @Test("Starting managed playback ends the external session")
    func managedPlaybackEndsExternalSession() async throws {
        let files = try ExternalAppModelFiles(names: ["External.flac"])
        defer { files.remove() }
        let managed = playbackTestTrack(id: UUID(), title: "Managed")
        let harness = externalModelHarness(
            metadataByURL: [
                files.urls[0]: appModelMetadata(title: "External"),
            ],
            managedTracks: [managed]
        )
        await harness.model.openExternalAudio(urls: files.urls)
        let externalID = try #require(
            harness.coordinator.state.currentTrack?.id
        )

        harness.model.playProductionTrack(
            libraryProjection(from: managed.track),
            within: [libraryProjection(from: managed.track)],
            source: .adHoc
        )
        for _ in 0 ..< 20 where harness.coordinator.state.currentTrack?.id != managed.track.id {
            await Task.yield()
        }

        #expect(harness.coordinator.state.currentTrack?.id == managed.track.id)
        #expect(harness.externalSession.item(id: externalID) == nil)
        #expect(!harness.model.isCurrentPlaybackExternal)
    }

    @Test("Add to Library sends only the current file to Scan and Review")
    func explicitImportUsesCurrentFileOnly() async throws {
        let files = try ExternalAppModelFiles(
            names: ["Current.flac", "Queued.mp3"]
        )
        defer { files.remove() }
        let inspector = ExternalImportInspector()
        let coordinator = ImportCoordinator(
            service: ImportInspectionService(
                inspector: inspector,
                duplicateLookup: ImportDuplicateLookup { _ in .empty }
            )
        )
        let harness = externalModelHarness(
            metadataByURL: [
                files.urls[0]: appModelMetadata(title: "Current"),
                files.urls[1]: appModelMetadata(title: "Queued"),
            ],
            importCoordinator: coordinator
        )
        await harness.model.openExternalAudio(urls: files.urls)

        harness.model.addCurrentExternalAudioToLibrary()

        for _ in 0 ..< 50 {
            if case .review = coordinator.state {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(harness.model.selectedDestination == .importMusic)
        #expect(await inspector.inspectedURLs() == [files.urls[0]])
        #expect(harness.model.isCurrentPlaybackExternal)
        #expect(harness.model.librarySession.store.catalogCounts == .empty)
        guard case let .review(candidates) = coordinator.state else {
            Issue.record("Expected exact-file import review")
            return
        }
        #expect(candidates.map(\.sourceFile.url) == [files.urls[0]])
    }
}

@MainActor
private struct ExternalModelHarness {
    let model: CadenceAppModel
    let coordinator: PlaybackCoordinator
    let externalSession: ExternalAudioSession
}

@MainActor
private func externalModelHarness(
    metadataByURL: [URL: ScannedAudioMetadata],
    managedTracks: [ResolvedPlaybackTrack] = [],
    importCoordinator: ImportCoordinator? = nil
) -> ExternalModelHarness {
    let externalSession = ExternalAudioSession(
        metadataReader: ExternalAppModelMetadataReader(
            metadataByURL: metadataByURL
        ),
        securityScope: ExternalAppModelSecurityScope()
    )
    let resolver = CompositePlaybackTrackResolver(
        external: externalSession,
        managed: PlaybackTestResolver(tracks: managedTracks)
    )
    let coordinator = makePlaybackCoordinator(
        resolver: resolver,
        backends: [PlaybackTestBackend(kind: .pcm)]
    )
    let model = CadenceAppModel(
        runtimeEnvironment: .production,
        importRuntimeAvailability: .available,
        librarySession: .preview(),
        importCoordinator: importCoordinator,
        playbackCoordinator: coordinator,
        externalAudioSession: externalSession
    )
    return ExternalModelHarness(
        model: model,
        coordinator: coordinator,
        externalSession: externalSession
    )
}

private actor ExternalImportInspector: ImportFileInspecting {
    private var urls: [URL] = []

    func inspect(
        audio: ScannedSourceFile,
        among _: [ScannedSourceFile]
    ) async throws -> ImportInspectionDraft {
        urls.append(audio.url)
        return ImportInspectionDraft(
            sourceFile: audio,
            sizeInBytes: 1,
            metadata: appModelMetadata(title: "Current"),
            contentHash: "external-current",
            lyrics: .unavailable,
            failure: nil
        )
    }

    func inspectedURLs() -> [URL] {
        urls
    }
}

private actor ExternalAppModelMetadataReader: AudioMetadataReading {
    let metadataByURL: [URL: ScannedAudioMetadata]

    init(metadataByURL: [URL: ScannedAudioMetadata]) {
        self.metadataByURL = metadataByURL
    }

    func read(url: URL) async throws -> ScannedAudioMetadata {
        guard let metadata = metadataByURL[url] else {
            throw MetadataReaderError.noAudioTrack(url.path)
        }
        return metadata
    }

    func readEmbeddedArtwork(url _: URL) async -> EmbeddedArtworkPayload? {
        nil
    }
}

@MainActor
private final class ExternalAppModelSecurityScope: SecurityScopedResourceAccessing {
    func startAccessing(_: URL) -> Bool {
        true
    }

    func stopAccessing(_: URL) {}
}

private struct ExternalAppModelFiles {
    let root: URL
    let urls: [URL]

    init(names: [String]) throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CadenceExternalAppModelTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        self.root = root
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        urls = try names.map { name in
            let url = root.appending(path: name).standardizedFileURL
            try Data(name.utf8).write(to: url)
            return url
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func appModelMetadata(title: String) -> ScannedAudioMetadata {
    ScannedAudioMetadata(
        title: title,
        artist: "External Artist",
        album: "External Album",
        year: 2026,
        trackNumber: 1,
        discNumber: 1,
        duration: 120,
        codec: "FLAC",
        container: "FLAC",
        sampleRate: 48000,
        channelCount: 2,
        bitrate: nil,
        bitDepth: 24,
        spatialFormat: .stereo
    )
}

private func libraryProjection(
    from track: PlaybackTrack
) -> LibraryTrackProjection {
    LibraryTrackProjection(
        id: track.id,
        title: track.title,
        artistID: track.artistID,
        artist: track.artist,
        albumID: track.albumID,
        album: track.album,
        duration: track.duration,
        year: track.year,
        codec: track.codec,
        sampleRate: track.sampleRate,
        channelCount: track.channelCount,
        bitDepth: track.bitDepth,
        isFavorite: false,
        customArtworkID: nil,
        artworkID: track.artworkID,
        relativeMediaPath: track.relativeMediaPath,
        lastPlayedAt: nil,
        hasSynchronizedLyrics: false
    )
}
