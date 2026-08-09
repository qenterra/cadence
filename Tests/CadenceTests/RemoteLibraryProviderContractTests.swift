@testable import Cadence
import Foundation
import Testing

struct RemoteLibraryProviderContractTests {
    @Test("A stale manifest revision fails closed")
    func staleManifestRevisionFailsClosed() async throws {
        let fixture = RemoteProviderFixture()
        let first = try await fixture.provider.fetchManifest(ifNoneMatch: nil)
        await fixture.provider.simulateConcurrentCommit()

        await #expect(throws: RemoteProviderError.conflict) {
            try await fixture.provider.commitManifest(
                fixture.updatedManifest,
                matching: first.revision
            )
        }
    }

    @Test("Conditional manifest fetch reports not modified")
    func conditionalManifestFetch() async throws {
        let fixture = RemoteProviderFixture()
        let first = try await fixture.provider.fetchManifest(ifNoneMatch: nil)
        let unchanged = try await fixture.provider.fetchManifest(
            ifNoneMatch: first.revision
        )

        #expect(first.manifest != nil)
        #expect(unchanged.manifest == nil)
        #expect(unchanged.revision == first.revision)
    }

    @Test("Object reads honor byte ranges")
    func objectReadsHonorRanges() async throws {
        let fixture = RemoteProviderFixture()
        let stream = try await fixture.provider.read(
            object: fixture.media.id,
            range: 2 ..< 6
        )

        #expect(try await stream.collected() == Data("2345".utf8))
    }

    @Test("Finalization rejects a mismatched content hash")
    func finalizeRejectsMismatchedHash() async throws {
        let fixture = RemoteProviderFixture()
        let upload = try await fixture.provider.uploadTemporary(
            object: fixture.media.id,
            bytes: .bytes(Data("replacement".utf8))
        )

        await #expect(throws: RemoteProviderError.integrityMismatch) {
            try await fixture.provider.finalize(
                upload,
                expectedSHA256: String(repeating: "0", count: 64)
            )
        }
    }

    @Test("The remote manifest round trips all portable references")
    func manifestRoundTrip() throws {
        let fixture = RemoteProviderFixture()
        let data = try JSONEncoder().encode(fixture.manifest)
        let decoded = try JSONDecoder().decode(
            RemoteLibraryManifest.self,
            from: data
        )

        #expect(decoded == fixture.manifest)
        #expect(decoded.schemaVersion == RemoteLibraryManifest.currentSchemaVersion)
        #expect(decoded.tracks.first?.artwork != nil)
        #expect(decoded.tracks.first?.lyrics != nil)
    }
}

private struct RemoteProviderFixture {
    let media = RemoteMediaObject(
        id: RemoteObjectID("media/track.flac"),
        byteCount: 10,
        sha256: "84d89877f0d4041efb6bf91a16f0248f2fd573e6af05c19f96bedb9f882f7882",
        fileExtension: "flac"
    )
    let manifest: RemoteLibraryManifest
    let updatedManifest: RemoteLibraryManifest
    let provider: FakeRemoteLibraryProvider

    init() {
        let artwork = RemoteBlobReference(
            id: RemoteObjectID("artwork/cover.jpg"),
            byteCount: 5,
            sha256: String(repeating: "a", count: 64)
        )
        let lyrics = RemoteBlobReference(
            id: RemoteObjectID("lyrics/track.lrc"),
            byteCount: 6,
            sha256: String(repeating: "b", count: 64)
        )
        manifest = RemoteLibraryManifest(
            libraryID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            generation: 1,
            tracks: [
                RemoteTrackManifestEntry(
                    trackID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    media: media,
                    artwork: artwork,
                    lyrics: lyrics
                ),
            ]
        )
        updatedManifest = RemoteLibraryManifest(
            libraryID: manifest.libraryID,
            generation: 2,
            tracks: manifest.tracks
        )
        provider = FakeRemoteLibraryProvider(
            manifest: manifest,
            objects: [media.id: Data("0123456789".utf8)]
        )
    }
}

private actor FakeRemoteLibraryProvider: RemoteLibraryProvider {
    private var manifest: RemoteLibraryManifest
    private var revision = "revision-1"
    private var objects: [RemoteObjectID: Data]
    private var temporaryUploads: [UUID: (RemoteObjectID, Data)] = [:]

    init(
        manifest: RemoteLibraryManifest,
        objects: [RemoteObjectID: Data]
    ) {
        self.manifest = manifest
        self.objects = objects
    }

    func restoreSession() async throws {}

    func fetchManifest(
        ifNoneMatch revision: String?
    ) async throws -> RemoteManifestResponse {
        RemoteManifestResponse(
            manifest: revision == self.revision ? nil : manifest,
            revision: self.revision
        )
    }

    func read(
        object: RemoteObjectID,
        range: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        guard let bytes = objects[object] else {
            throw RemoteProviderError.objectNotFound(object)
        }
        let selected: Data
        if let range {
            guard range.lowerBound >= 0,
                  range.upperBound <= Int64(bytes.count)
            else {
                throw RemoteProviderError.invalidRange
            }
            selected = bytes.subdata(
                in: Int(range.lowerBound) ..< Int(range.upperBound)
            )
        } else {
            selected = bytes
        }
        return .bytes(selected)
    }

    func uploadTemporary(
        object: RemoteObjectID,
        bytes: AsyncThrowingStream<Data, Error>
    ) async throws -> RemoteUpload {
        let id = UUID()
        temporaryUploads[id] = try await (object, bytes.collected())
        return RemoteUpload(id: id, object: object)
    }

    func finalize(
        _ upload: RemoteUpload,
        expectedSHA256: String
    ) async throws {
        guard let pending = temporaryUploads.removeValue(forKey: upload.id) else {
            throw RemoteProviderError.objectNotFound(upload.object)
        }
        guard ContentHasher().sha256(of: pending.1) == expectedSHA256 else {
            throw RemoteProviderError.integrityMismatch
        }
        objects[pending.0] = pending.1
    }

    func commitManifest(
        _ manifest: RemoteLibraryManifest,
        matching revision: String?
    ) async throws -> String {
        guard revision == self.revision else {
            throw RemoteProviderError.conflict
        }
        self.manifest = manifest
        self.revision = "revision-\(manifest.generation)"
        return self.revision
    }

    func delete(object: RemoteObjectID) async throws {
        objects[object] = nil
    }

    func simulateConcurrentCommit() {
        revision = "revision-concurrent"
    }
}

private extension AsyncThrowingStream where Element == Data, Failure == Error {
    static func bytes(_ data: Data) -> Self {
        AsyncThrowingStream { continuation in
            continuation.yield(data)
            continuation.finish()
        }
    }

    func collected() async throws -> Data {
        var result = Data()
        for try await chunk in self {
            result.append(chunk)
        }
        return result
    }
}
