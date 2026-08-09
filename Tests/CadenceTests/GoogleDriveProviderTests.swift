@testable import Cadence
import Foundation
import Testing

@Suite(.serialized)
struct GoogleDriveProviderTests {
    @Test("Manifest downloads carry a fresh bearer token and ETag")
    func fetchManifest() async throws {
        let fixture = GoogleDriveFixture()
        GoogleDriveURLProtocolStub.install { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-token")
            #expect(request.url?.path.hasSuffix("/files/manifest-id") == true)
            #expect(request.url?.query?.contains("alt=media") == true)
            return try .response(
                request,
                status: 200,
                headers: ["ETag": "drive-revision-1"],
                body: JSONEncoder().encode(fixture.manifest)
            )
        }

        let response = try await fixture.provider.fetchManifest(ifNoneMatch: nil)

        #expect(response.manifest == fixture.manifest)
        #expect(response.revision == "drive-revision-1")
        #expect(await fixture.authorization.tokenRequests == 1)
    }

    @Test("Media reads resolve logical IDs and preserve Range")
    func rangeRead() async throws {
        let fixture = GoogleDriveFixture()
        GoogleDriveURLProtocolStub.install { request in
            if request.url?.query?.contains("q=") == true {
                return .response(
                    request,
                    status: 200,
                    body: Data(#"{"files":[{"id":"drive-media-id"}]}"#.utf8)
                )
            }
            #expect(request.url?.path.hasSuffix("/files/drive-media-id") == true)
            #expect(request.value(forHTTPHeaderField: "Range") == "bytes=2-5")
            return .response(request, status: 206, body: Data("2345".utf8))
        }

        let stream = try await fixture.provider.read(
            object: fixture.object.id,
            range: 2 ..< 6
        )

        #expect(try await stream.googleCollected() == Data("2345".utf8))
    }

    @Test("Resumable upload is finalized only after local hash verification")
    func resumableUpload() async throws {
        let fixture = GoogleDriveFixture()
        let lock = NSLock()
        nonisolated(unsafe) var requestNumber = 0
        GoogleDriveURLProtocolStub.install { request in
            let number = lock.withLock {
                requestNumber += 1
                return requestNumber
            }
            switch number {
            case 1:
                #expect(request.httpMethod == "POST")
                #expect(request.url?.query?.contains("uploadType=resumable") == true)
                return .response(
                    request,
                    status: 200,
                    headers: ["Location": "https://upload.example.test/session"]
                )
            case 2:
                #expect(request.httpMethod == "PUT")
                return .response(
                    request,
                    status: 200,
                    body: Data(#"{"id":"temporary-drive-id"}"#.utf8)
                )
            default:
                #expect(request.httpMethod == "PATCH")
                #expect(request.url?.path.hasSuffix("/files/temporary-drive-id") == true)
                return .response(request, status: 200)
            }
        }
        let bytes = Data("0123456789".utf8)

        let upload = try await fixture.provider.uploadTemporary(
            object: fixture.object.id,
            bytes: .googleBytes(bytes)
        )
        try await fixture.provider.finalize(
            upload,
            expectedSHA256: fixture.object.sha256
        )

        let finalRequestCount = lock.withLock { requestNumber }
        #expect(finalRequestCount == 3)
    }

    @Test("Drive precondition failure maps to a conflict")
    func manifestConflict() async throws {
        let fixture = GoogleDriveFixture()
        GoogleDriveURLProtocolStub.install { request in
            #expect(request.httpMethod == "PATCH")
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

    @Test("Provider sign-out deletes the authorization state")
    func signOut() async throws {
        let fixture = GoogleDriveFixture()

        try await fixture.provider.signOut()

        #expect(await fixture.authorization.didSignOut)
    }
}

private struct GoogleDriveFixture: Sendable {
    let object: RemoteMediaObject
    let manifest: RemoteLibraryManifest
    let authorization: GoogleDriveAuthorizationStub
    let provider: GoogleDriveProvider

    init() {
        let bytes = Data("0123456789".utf8)
        object = RemoteMediaObject(
            id: RemoteObjectID("media/test.flac"),
            byteCount: Int64(bytes.count),
            sha256: ContentHasher().sha256(of: bytes),
            fileExtension: "flac"
        )
        manifest = RemoteLibraryManifest(
            libraryID: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            generation: 1,
            tracks: [
                RemoteTrackManifestEntry(
                    trackID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
                    media: object,
                    artwork: nil,
                    lyrics: nil
                ),
            ]
        )
        authorization = GoogleDriveAuthorizationStub()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GoogleDriveURLProtocolStub.self]
        provider = GoogleDriveProvider(
            configuration: GoogleDriveConfiguration(
                folderID: "folder-id",
                manifestFileID: "manifest-id"
            ),
            session: URLSession(configuration: configuration),
            authorization: authorization
        )
    }
}

private actor GoogleDriveAuthorizationStub: GoogleDriveAuthorizing {
    private(set) var tokenRequests = 0
    private(set) var didSignOut = false

    func restoreSession() async throws {}

    func accessToken() async throws -> String {
        tokenRequests += 1
        return "fresh-token"
    }

    func signOut() async throws {
        didSignOut = true
    }
}

private final class GoogleDriveURLProtocolStub: URLProtocol, @unchecked Sendable {
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
    static func googleBytes(_ data: Data) -> Self {
        AsyncThrowingStream { continuation in
            continuation.yield(data)
            continuation.finish()
        }
    }

    func googleCollected() async throws -> Data {
        var data = Data()
        for try await chunk in self {
            data.append(chunk)
        }
        return data
    }
}
