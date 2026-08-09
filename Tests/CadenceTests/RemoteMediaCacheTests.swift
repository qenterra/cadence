@testable import Cadence
import Foundation
import Testing

struct RemoteMediaCacheTests {
    @Test("An incomplete object never becomes playable")
    func incompleteObjectNeverBecomesPlayable() async throws {
        let fixture = try RemoteMediaCacheFixture(budget: 100)
        defer { fixture.cleanup() }
        await fixture.provider.setFailure(afterBytes: 3)

        await #expect(throws: RemoteProviderError.interrupted) {
            try await fixture.cache.localURL(for: fixture.first)
        }

        #expect(await fixture.cache.playableURL(for: fixture.first.id) == nil)
        #expect(try FileManager.default.contentsOfDirectory(
            at: fixture.stagingURL,
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test("A hash mismatch never enters the playable cache")
    func hashMismatchNeverBecomesPlayable() async throws {
        let fixture = try RemoteMediaCacheFixture(budget: 100)
        defer { fixture.cleanup() }
        let invalid = RemoteMediaObject(
            id: fixture.first.id,
            byteCount: fixture.first.byteCount,
            sha256: String(repeating: "0", count: 64),
            fileExtension: fixture.first.fileExtension
        )

        await #expect(throws: RemoteProviderError.integrityMismatch) {
            try await fixture.cache.localURL(for: invalid)
        }

        #expect(await fixture.cache.playableURL(for: invalid.id) == nil)
    }

    @Test("Eviction keeps pinned current and next tracks")
    func evictionKeepsPinnedCurrentAndNext() async throws {
        let fixture = try RemoteMediaCacheFixture(budget: 20)
        defer { fixture.cleanup() }
        await fixture.cache.pin([fixture.first.id, fixture.second.id])

        _ = try await fixture.cache.localURL(for: fixture.first)
        _ = try await fixture.cache.localURL(for: fixture.second)
        await fixture.cache.prefetch(fixture.third)

        #expect(await fixture.cache.playableURL(for: fixture.first.id) != nil)
        #expect(await fixture.cache.playableURL(for: fixture.second.id) != nil)
        #expect(await fixture.cache.playableURL(for: fixture.third.id) == nil)
    }

    @Test("A verified cache hit does not download twice")
    func verifiedCacheHitDoesNotDownloadTwice() async throws {
        let fixture = try RemoteMediaCacheFixture(budget: 100)
        defer { fixture.cleanup() }

        let firstURL = try await fixture.cache.localURL(for: fixture.first)
        let secondURL = try await fixture.cache.localURL(for: fixture.first)

        #expect(firstURL == secondURL)
        #expect(await fixture.provider.readCount(for: fixture.first.id) == 1)
    }

    @Test("The cache index survives a new cache actor")
    func cacheIndexSurvivesRestart() async throws {
        let fixture = try RemoteMediaCacheFixture(budget: 100)
        defer { fixture.cleanup() }
        let expected = try await fixture.cache.localURL(for: fixture.first)

        let reopened = RemoteMediaCache(
            rootURL: fixture.rootURL,
            budgetBytes: 100,
            provider: fixture.provider
        )

        #expect(await reopened.playableURL(for: fixture.first.id) == expected)
    }

    @Test("A corrupted cache index cannot escape the cache root")
    func corruptedIndexCannotEscapeCacheRoot() async throws {
        let fixture = try RemoteMediaCacheFixture(budget: 100)
        defer { fixture.cleanup() }
        let victim = fixture.rootURL.deletingLastPathComponent().appending(
            path: "Cadence-Cache-Victim-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: victim) }
        try Data("keep".utf8).write(to: victim)
        let malicious = RemoteCacheIndex(entries: [
            RemoteCacheEntry(
                object: fixture.first,
                relativePath: "Objects/../../\(victim.lastPathComponent)",
                lastAccessedAt: .now
            ),
        ])
        try JSONEncoder().encode(malicious).write(
            to: fixture.rootURL.appending(path: "CacheIndex.json"),
            options: .atomic
        )

        let reopened = RemoteMediaCache(
            rootURL: fixture.rootURL,
            budgetBytes: 100,
            provider: fixture.provider
        )

        #expect(await reopened.playableURL(for: fixture.first.id) == nil)
        #expect(FileManager.default.fileExists(atPath: victim.path))
    }
}

private struct RemoteMediaCacheFixture {
    let rootURL: URL
    let provider: RemoteCacheProviderStub
    let cache: RemoteMediaCache
    let first: RemoteMediaObject
    let second: RemoteMediaObject
    let third: RemoteMediaObject

    var stagingURL: URL {
        rootURL.appending(path: "Staging", directoryHint: .isDirectory)
    }

    init(budget: Int64) throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Remote-Cache-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let firstBytes = Data("0123456789".utf8)
        let secondBytes = Data("abcdefghij".utf8)
        let thirdBytes = Data("KLMNOPQRST".utf8)
        first = Self.object(name: "first", bytes: firstBytes)
        second = Self.object(name: "second", bytes: secondBytes)
        third = Self.object(name: "third", bytes: thirdBytes)
        provider = RemoteCacheProviderStub(objects: [
            first.id: firstBytes,
            second.id: secondBytes,
            third.id: thirdBytes,
        ])
        cache = RemoteMediaCache(
            rootURL: rootURL,
            budgetBytes: budget,
            provider: provider
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func object(
        name: String,
        bytes: Data
    ) -> RemoteMediaObject {
        RemoteMediaObject(
            id: RemoteObjectID("media/\(name).flac"),
            byteCount: Int64(bytes.count),
            sha256: ContentHasher().sha256(of: bytes),
            fileExtension: "flac"
        )
    }
}

private actor RemoteCacheProviderStub: RemoteLibraryProvider {
    private let objects: [RemoteObjectID: Data]
    private var reads: [RemoteObjectID: Int] = [:]
    private var failureAfterBytes: Int?

    init(objects: [RemoteObjectID: Data]) {
        self.objects = objects
    }

    func setFailure(afterBytes: Int?) {
        failureAfterBytes = afterBytes
    }

    func readCount(for object: RemoteObjectID) -> Int {
        reads[object, default: 0]
    }

    func restoreSession() async throws {}

    func fetchManifest(ifNoneMatch _: String?) async throws -> RemoteManifestResponse {
        throw RemoteProviderError.serviceUnavailable("unused by cache tests")
    }

    func read(
        object: RemoteObjectID,
        range _: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        guard let bytes = objects[object] else {
            throw RemoteProviderError.objectNotFound(object)
        }
        reads[object, default: 0] += 1
        let failureAfterBytes = failureAfterBytes
        return AsyncThrowingStream { continuation in
            if let failureAfterBytes {
                continuation.yield(bytes.prefix(failureAfterBytes))
                continuation.finish(throwing: RemoteProviderError.interrupted)
            } else {
                continuation.yield(bytes)
                continuation.finish()
            }
        }
    }

    func uploadTemporary(
        object _: RemoteObjectID,
        bytes _: AsyncThrowingStream<Data, Error>
    ) async throws -> RemoteUpload {
        throw RemoteProviderError.serviceUnavailable("unused by cache tests")
    }

    func finalize(
        _: RemoteUpload,
        expectedSHA256 _: String
    ) async throws {
        throw RemoteProviderError.serviceUnavailable("unused by cache tests")
    }

    func commitManifest(
        _: RemoteLibraryManifest,
        matching _: String?
    ) async throws -> String {
        throw RemoteProviderError.serviceUnavailable("unused by cache tests")
    }

    func delete(object _: RemoteObjectID) async throws {
        throw RemoteProviderError.serviceUnavailable("unused by cache tests")
    }
}
