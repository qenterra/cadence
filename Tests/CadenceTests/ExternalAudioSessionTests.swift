@testable import Cadence
import Foundation
import Testing

@MainActor
struct ExternalAudioSessionTests {
    @Test("Exact supported files keep order without directory scanning")
    func exactFilesKeepOrder() async throws {
        let fixture = try ExternalAudioFixture()
        defer { fixture.remove() }

        let first = try fixture.file(named: "First.flac")
        let second = try fixture.file(named: "Second.mp3")
        let unsupported = try fixture.file(named: "Notes.txt")
        let nested = try fixture.file(named: "Nested/Hidden.wav")
        let reader = ExternalAudioMetadataReaderStub(
            metadataByURL: [
                first: externalMetadata(title: "First", container: "FLAC"),
                second: externalMetadata(title: "Second", container: "MP3"),
                nested: externalMetadata(title: "Hidden", container: "WAV"),
            ]
        )
        let access = RecordingSecurityScopeAccess()
        let session = ExternalAudioSession(
            metadataReader: reader,
            securityScope: access
        )

        let result = await session.prepare(
            urls: [second, first, second, unsupported, fixture.root]
        )

        #expect(result.items.map(\.sourceURL) == [second, first])
        #expect(result.items.map(\.resolvedTrack.track.title) == ["Second", "First"])
        #expect(result.skippedCount == 2)
        #expect(await reader.metadataRequests == [second, first])
        #expect(await reader.artworkRequests == [second, first])
        #expect(access.started == [second, first])
        #expect(!access.started.contains(nested))
    }

    @Test("Embedded artwork stays transient and security access ends with session")
    func artworkAndAccessLifetime() async throws {
        let fixture = try ExternalAudioFixture()
        defer { fixture.remove() }

        let file = try fixture.file(named: "Artwork.m4a")
        let artworkData = Data("artwork".utf8)
        let reader = ExternalAudioMetadataReaderStub(
            metadataByURL: [
                file: externalMetadata(title: "Artwork", container: "M4A"),
            ],
            artworkByURL: [
                file: EmbeddedArtworkPayload(
                    metadata: EmbeddedArtworkMetadata(
                        contentHash: String(repeating: "a", count: 64),
                        format: "png",
                        pixelWidth: 32,
                        pixelHeight: 32
                    ),
                    data: artworkData
                ),
            ]
        )
        let access = RecordingSecurityScopeAccess()
        let session = ExternalAudioSession(
            metadataReader: reader,
            securityScope: access
        )

        let result = await session.prepare(urls: [file])
        let item = try #require(result.items.first)
        #expect(item.artwork?.data == artworkData)

        session.replace(with: result.items)
        #expect(session.item(id: item.id)?.sourceURL == file)
        session.end()
        #expect(access.stopped == [file])
        #expect(session.item(id: item.id) == nil)
    }

    @Test("A batch without readable supported files cannot replace playback")
    func allInvalid() async throws {
        let fixture = try ExternalAudioFixture()
        defer { fixture.remove() }

        let unsupported = try fixture.file(named: "Cover.jpg")
        let missing = fixture.root.appending(path: "Missing.flac")
        let session = ExternalAudioSession(
            metadataReader: ExternalAudioMetadataReaderStub(metadataByURL: [:]),
            securityScope: RecordingSecurityScopeAccess()
        )

        let result = await session.prepare(urls: [unsupported, missing])

        #expect(result.items.isEmpty)
        #expect(result.skippedCount == 2)
        #expect(result.failures.count == 1)
    }
}

private actor ExternalAudioMetadataReaderStub: AudioMetadataReading {
    let metadataByURL: [URL: ScannedAudioMetadata]
    let artworkByURL: [URL: EmbeddedArtworkPayload]
    private(set) var metadataRequests: [URL] = []
    private(set) var artworkRequests: [URL] = []

    init(
        metadataByURL: [URL: ScannedAudioMetadata],
        artworkByURL: [URL: EmbeddedArtworkPayload] = [:]
    ) {
        self.metadataByURL = metadataByURL
        self.artworkByURL = artworkByURL
    }

    func read(url: URL) async throws -> ScannedAudioMetadata {
        metadataRequests.append(url)
        guard let metadata = metadataByURL[url] else {
            throw MetadataReaderError.noAudioTrack(url.path)
        }
        return metadata
    }

    func readEmbeddedArtwork(url: URL) async -> EmbeddedArtworkPayload? {
        artworkRequests.append(url)
        return artworkByURL[url]
    }
}

@MainActor
private final class RecordingSecurityScopeAccess: SecurityScopedResourceAccessing {
    private(set) var started: [URL] = []
    private(set) var stopped: [URL] = []

    func startAccessing(_ url: URL) -> Bool {
        started.append(url)
        return true
    }

    func stopAccessing(_ url: URL) {
        stopped.append(url)
    }
}

private struct ExternalAudioFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "CadenceExternalAudioTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    func file(named relativePath: String) throws -> URL {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(relativePath.utf8).write(to: url)
        return url.standardizedFileURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func externalMetadata(
    title: String,
    container: String
) -> ScannedAudioMetadata {
    ScannedAudioMetadata(
        title: title,
        artist: "External Artist",
        album: "External Album",
        year: 2026,
        trackNumber: 1,
        discNumber: 1,
        duration: 90,
        codec: container,
        container: container,
        sampleRate: 48000,
        channelCount: 2,
        bitrate: 320_000,
        bitDepth: 24,
        spatialFormat: .stereo
    )
}
