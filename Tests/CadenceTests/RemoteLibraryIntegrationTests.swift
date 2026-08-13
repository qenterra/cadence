@testable import Cadence
import Foundation
import SwiftData
import Testing

@MainActor
struct RemoteLibraryIntegrationTests {
    @Test("Current track buffers, then plays, while the next track prefetches")
    func currentBuffersThenPlaysAndNextPrefetches() async throws {
        let fixture = try await RemotePlaybackFixture()
        defer { fixture.remove() }

        let playback = Task {
            await fixture.coordinator.startQueue(
                source: .adHoc,
                trackIDs: [fixture.currentID, fixture.nextID]
            )
        }
        try await waitUntil {
            await fixture.provider.hasRequest(for: fixture.currentObject.id)
        }

        #expect(fixture.coordinator.state.transport == .loading)
        #expect(fixture.coordinator.state.isBuffering)

        await fixture.provider.release(fixture.currentObject.id)
        try await waitUntil {
            fixture.coordinator.state.transport == .playing
        }

        #expect(fixture.backend.loadRequests.first?.current.track.id == fixture.currentID)
        #expect(
            fixture.backend.loadRequests.first?.current.mediaURL.path.contains(
                fixture.currentObject.sha256
            ) == true
        )
        try await waitUntil {
            await fixture.provider.hasRequest(for: fixture.nextObject.id)
        }
        await fixture.provider.release(fixture.nextObject.id)
        _ = await playback.value
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        for _ in 0 ..< 300 {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for remote playback state")
    }
}

@MainActor
private final class RemotePlaybackFixture {
    let rootURL: URL
    let currentID = UUID()
    let nextID = UUID()
    let currentObject: RemoteMediaObject
    let nextObject: RemoteMediaObject
    let provider: SuspendedRemoteProvider
    let backend = PlaybackTestBackend(kind: .pcm)
    let coordinator: PlaybackCoordinator

    init() async throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Remote-Integration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let cacheURL = rootURL.appending(path: "Cache", directoryHint: .isDirectory)
        let currentBytes = Data("current-audio".utf8)
        let nextBytes = Data("next-audio".utf8)
        currentObject = Self.object(
            id: currentID,
            name: "current",
            bytes: currentBytes
        )
        nextObject = Self.object(
            id: nextID,
            name: "next",
            bytes: nextBytes
        )
        let session = try Self.makeLibrarySession(
            rootURL: rootURL,
            tracks: [
                RemoteFixtureTrack(
                    id: currentID,
                    title: "Current",
                    hash: currentObject.sha256
                ),
                RemoteFixtureTrack(
                    id: nextID,
                    title: "Next",
                    hash: nextObject.sha256
                ),
            ]
        )
        provider = SuspendedRemoteProvider(objects: [
            currentObject.id: currentBytes,
            nextObject.id: nextBytes,
        ])
        let source = try await Self.makeSource(
            provider: provider,
            current: (currentID, currentObject),
            next: (nextID, nextObject),
            cacheURL: cacheURL
        )
        coordinator = makePlaybackCoordinator(
            resolver: ManagedPlaybackTrackResolver(
                librarySession: session,
                remoteSource: source
            ),
            backends: [backend]
        )
    }

    func remove() {
        coordinator.shutdown()
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func object(
        id: UUID,
        name: String,
        bytes: Data
    ) -> RemoteMediaObject {
        RemoteMediaObject(
            id: RemoteObjectID("media/\(id.uuidString)-\(name).flac"),
            byteCount: Int64(bytes.count),
            sha256: ContentHasher().sha256(of: bytes),
            fileExtension: "flac"
        )
    }

    private static func makeLibrarySession(
        rootURL: URL,
        tracks: [RemoteFixtureTrack]
    ) throws -> LibrarySession {
        let musicURL = rootURL.appending(path: "Music", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: musicURL,
            withIntermediateDirectories: true
        )
        let package = ManagedLibraryPackage(
            location: ManagedLibraryLocation(musicDirectory: musicURL)
        )
        try package.bootstrapForConfirmedImport()
        try package.writeIdentity(LibraryIdentity())
        let container = try LibraryContainerFactory.persistent(package: package)
        for track in tracks {
            try insertTrack(
                id: track.id,
                title: track.title,
                hash: track.hash,
                in: container
            )
        }
        return LibrarySession.startup(location: package.location)
    }

    private static func makeSource(
        provider: SuspendedRemoteProvider,
        current: (id: UUID, object: RemoteMediaObject),
        next: (id: UUID, object: RemoteMediaObject),
        cacheURL: URL
    ) async throws -> RemotePlaybackSource {
        let source = RemotePlaybackSource()
        let tracks = [current, next].map {
            RemoteTrackManifestEntry(
                trackID: $0.id,
                media: $0.object,
                artwork: nil,
                lyrics: nil
            )
        }
        try await source.activate(
            provider: provider,
            manifest: RemoteLibraryManifest(
                libraryID: UUID(),
                generation: 1,
                tracks: tracks
            ),
            cacheRootURL: cacheURL,
            budgetBytes: 1024
        )
        return source
    }

    private static func insertTrack(
        id: UUID,
        title: String,
        hash: String,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        context.insert(
            TrackRecord(
                id: id,
                originalFilename: "\(title).flac",
                title: title,
                duration: 120,
                codec: "FLAC",
                container: "FLAC",
                sampleRate: 48000,
                channelCount: 2,
                bitDepth: 24,
                contentHash: hash,
                relativeMediaPath: "Media/\(id.uuidString).flac",
                importSessionID: UUID()
            )
        )
        try context.save()
    }
}

private struct RemoteFixtureTrack {
    let id: UUID
    let title: String
    let hash: String
}

private actor SuspendedRemoteProvider: RemoteLibraryProvider {
    private let objects: [RemoteObjectID: Data]
    private var requests: Set<RemoteObjectID> = []
    private var continuations: [
        RemoteObjectID: AsyncThrowingStream<Data, Error>.Continuation
    ] = [:]

    init(objects: [RemoteObjectID: Data]) {
        self.objects = objects
    }

    func hasRequest(
        for object: RemoteObjectID
    ) -> Bool {
        requests.contains(object)
    }

    func release(
        _ object: RemoteObjectID
    ) {
        guard let bytes = objects[object],
              let continuation = continuations.removeValue(forKey: object)
        else {
            return
        }
        continuation.yield(bytes)
        continuation.finish()
    }

    func restoreSession() async throws {}

    func fetchManifest(ifNoneMatch _: String?) async throws -> RemoteManifestResponse {
        throw RemoteProviderError.serviceUnavailable("unused")
    }

    func read(
        object: RemoteObjectID,
        range _: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        guard objects[object] != nil else {
            throw RemoteProviderError.objectNotFound(object)
        }
        requests.insert(object)
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        continuations[object] = continuation
        return stream
    }

    func uploadTemporary(
        object _: RemoteObjectID,
        bytes _: AsyncThrowingStream<Data, Error>
    ) async throws -> RemoteUpload {
        throw RemoteProviderError.serviceUnavailable("unused")
    }

    func finalize(_: RemoteUpload, expectedSHA256 _: String) async throws {}

    func commitManifest(
        _: RemoteLibraryManifest,
        matching _: String?
    ) async throws -> String {
        throw RemoteProviderError.serviceUnavailable("unused")
    }

    func delete(object _: RemoteObjectID) async throws {}
}
