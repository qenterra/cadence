@testable import Cadence
import Foundation
import Testing

@Suite(.serialized)
struct WebDAVProviderTests {
    @Test("PROPFIND reports WebDAV and range capabilities")
    func capabilityDiscovery() async throws {
        let fixture = await WebDAVFixture()
        WebDAVURLProtocolStub.install { request in
            #expect(request.httpMethod == "PROPFIND")
            #expect(request.value(forHTTPHeaderField: "Depth") == "0")
            return .response(
                request,
                status: 207,
                headers: ["DAV": "1, 2", "Accept-Ranges": "bytes"]
            )
        }

        let capabilities = try await fixture.provider.capabilities()

        #expect(capabilities.supportsClass1)
        #expect(capabilities.supportsClass2)
        #expect(capabilities.supportsByteRanges)
    }

    @Test("Manifest fetch decodes content and preserves ETag")
    func fetchManifest() async throws {
        let fixture = await WebDAVFixture()
        WebDAVURLProtocolStub.install { request in
            #expect(request.url?.lastPathComponent == "Manifest.json")
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "old")
            return try .response(
                request,
                status: 200,
                headers: ["ETag": "revision-2"],
                body: JSONEncoder().encode(fixture.manifest)
            )
        }

        let response = try await fixture.provider.fetchManifest(ifNoneMatch: "old")

        #expect(response.manifest == fixture.manifest)
        #expect(response.revision == "revision-2")
    }

    @Test("A range read requires a partial response")
    func rangeRead() async throws {
        let fixture = await WebDAVFixture()
        WebDAVURLProtocolStub.install { request in
            #expect(request.value(forHTTPHeaderField: "Range") == "bytes=2-5")
            return .response(
                request,
                status: 206,
                headers: ["Content-Range": "bytes 2-5/10"],
                body: Data("2345".utf8)
            )
        }

        let stream = try await fixture.provider.read(
            object: fixture.object.id,
            range: 2 ..< 6
        )

        #expect(try await stream.webDAVCollected() == Data("2345".utf8))
    }

    @Test("A server that ignores Range fails honestly")
    func unsupportedRange() async throws {
        let fixture = await WebDAVFixture()
        WebDAVURLProtocolStub.install { request in
            .response(request, status: 200, body: Data("0123456789".utf8))
        }

        await #expect(throws: RemoteProviderError.rangeNotSupported) {
            try await fixture.provider.read(
                object: fixture.object.id,
                range: 2 ..< 6
            )
        }
    }

    @Test("Manifest preconditions map to a conflict")
    func manifestConflict() async throws {
        let fixture = await WebDAVFixture()
        WebDAVURLProtocolStub.install { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.value(forHTTPHeaderField: "If-Match") == "stale")
            return .response(request, status: 412)
        }

        await #expect(throws: RemoteProviderError.conflict) {
            try await fixture.provider.commitManifest(
                fixture.manifest,
                matching: "stale"
            )
        }
    }

    @Test("Credentials are restored without exposing them in errors")
    func authenticationRestore() async throws {
        let store = InMemoryWebDAVCredentialStore()
        let credentials = WebDAVCredentials(username: "nikita", password: "secret")
        await store.save(credentials)
        let authentication = WebDAVAuthentication(
            key: "test",
            store: store
        )
        let fixture = await WebDAVFixture(authentication: authentication)
        WebDAVURLProtocolStub.install { request in
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
            return .response(request, status: 304, headers: ["ETag": "same"])
        }

        try await fixture.provider.restoreSession()
        let response = try await fixture.provider.fetchManifest(ifNoneMatch: "same")

        #expect(response.manifest == nil)
        #expect(response.revision == "same")
    }
}

private struct WebDAVFixture: Sendable {
    let object: RemoteMediaObject
    let manifest: RemoteLibraryManifest
    let provider: WebDAVProvider

    init(authentication: WebDAVAuthentication? = nil) async {
        let bytes = Data("0123456789".utf8)
        object = RemoteMediaObject(
            id: RemoteObjectID("media/test.flac"),
            byteCount: Int64(bytes.count),
            sha256: ContentHasher().sha256(of: bytes),
            fileExtension: "flac"
        )
        manifest = RemoteLibraryManifest(
            libraryID: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            generation: 1,
            tracks: [
                RemoteTrackManifestEntry(
                    trackID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                    media: object,
                    artwork: nil,
                    lyrics: nil
                ),
            ]
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WebDAVURLProtocolStub.self]
        provider = WebDAVProvider(
            rootURL: URL(string: "https://dav.example.test/Cadence/")!,
            session: URLSession(configuration: configuration),
            authentication: authentication ?? WebDAVAuthentication(
                key: "test",
                store: InMemoryWebDAVCredentialStore()
            )
        )
    }
}

private actor InMemoryWebDAVCredentialStore: WebDAVCredentialStoring {
    private var values: [String: WebDAVCredentials] = [:]

    func load(key: String) async throws -> WebDAVCredentials? {
        values[key]
    }

    func save(
        _ credentials: WebDAVCredentials,
        key: String
    ) async throws {
        values[key] = credentials
    }

    func delete(key: String) async throws {
        values[key] = nil
    }

    func save(_ credentials: WebDAVCredentials) {
        values["test"] = credentials
    }
}

private final class WebDAVURLProtocolStub: URLProtocol, @unchecked Sendable {
    struct StubResponse {
        let response: HTTPURLResponse
        let body: Data

        static func response(
            _ request: URLRequest,
            status: Int,
            headers: [String: String] = [:],
            body: Data = Data()
        ) -> Self {
            StubResponse(
                response: HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                )!,
                body: body
            )
        }
    }

    private nonisolated(unsafe) static var handler: ((URLRequest) throws -> StubResponse)?
    private static let lock = NSLock()

    static func install(
        _ handler: @escaping (URLRequest) throws -> StubResponse
    ) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            guard let handler else {
                throw URLError(.resourceUnavailable)
            }
            let result = try handler(request)
            client?.urlProtocol(self, didReceive: result.response, cacheStoragePolicy: .notAllowed)
            if !result.body.isEmpty {
                client?.urlProtocol(self, didLoad: result.body)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension AsyncThrowingStream where Element == Data, Failure == Error {
    func webDAVCollected() async throws -> Data {
        var data = Data()
        for try await chunk in self {
            data.append(chunk)
        }
        return data
    }
}
