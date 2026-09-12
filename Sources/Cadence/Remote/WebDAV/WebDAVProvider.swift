import Foundation

protocol WebDAVRemoteLibraryProvider: RemoteLibraryProvider {
    func capabilities() async throws -> WebDAVCapabilities
}

actor WebDAVProvider: WebDAVRemoteLibraryProvider {
    private let rootURL: URL
    private let session: URLSession
    private let authentication: WebDAVAuthentication

    init(
        rootURL: URL,
        session: URLSession = .shared,
        authentication: WebDAVAuthentication
    ) {
        self.rootURL = rootURL
        self.session = session
        self.authentication = authentication
    }

    func capabilities() async throws -> WebDAVCapabilities {
        var request = try await request(method: "PROPFIND", url: rootURL)
        request.setValue("0", forHTTPHeaderField: "Depth")
        let (_, response) = try await perform(request)
        guard response.statusCode == 207 || response.statusCode == 200 else {
            throw mappedError(response, object: nil)
        }
        let dav = response.value(forHTTPHeaderField: "DAV") ?? ""
        let classes = Set(
            dav.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        )
        let ranges = response.value(forHTTPHeaderField: "Accept-Ranges")
        return WebDAVCapabilities(
            supportsClass1: classes.contains("1"),
            supportsClass2: classes.contains("2"),
            supportsByteRanges: ranges?.localizedCaseInsensitiveContains("bytes") == true
        )
    }

    func fetchManifest(
        ifNoneMatch revision: String?
    ) async throws -> RemoteManifestResponse {
        var request = try await request(
            method: "GET",
            url: rootURL.appending(path: "Manifest.json")
        )
        if let revision {
            request.setValue(revision, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await perform(request)
        if response.statusCode == 304 {
            return try RemoteManifestResponse(
                manifest: nil,
                revision: RemoteRevision.notModified(
                    response: response.etag,
                    request: revision
                ).rawValue
            )
        }
        guard response.statusCode == 200 else {
            throw mappedError(response, object: nil)
        }
        let etag = try RemoteRevision(response.etag).rawValue
        let manifest: RemoteLibraryManifest
        do {
            manifest = try JSONDecoder().decode(
                RemoteLibraryManifest.self,
                from: data
            )
            try manifest.validate()
        } catch let error as RemoteProviderError {
            throw error
        } catch {
            throw RemoteProviderError.invalidManifest("invalid JSON payload")
        }
        return RemoteManifestResponse(manifest: manifest, revision: etag)
    }

    func read(
        object: RemoteObjectID,
        range: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        var request = try await request(
            method: "GET",
            url: objectURL(object)
        )
        if let range {
            guard !range.isEmpty,
                  range.lowerBound >= 0
            else {
                throw RemoteProviderError.invalidRange
            }
            request.setValue(
                "bytes=\(range.lowerBound)-\(range.upperBound - 1)",
                forHTTPHeaderField: "Range"
            )
        }
        let (data, response) = try await perform(request)
        if range != nil,
           response.statusCode == 200 {
            throw RemoteProviderError.rangeNotSupported
        }
        guard response.statusCode == 200 || response.statusCode == 206 else {
            throw mappedError(response, object: object)
        }
        return Self.stream(data)
    }
}

private extension WebDAVProvider {
    func request(
        method: String,
        url: URL
    ) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Cadence/0.1", forHTTPHeaderField: "User-Agent")
        if let authorization = await authentication.authorizationHeader() {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func objectURL(
        _ object: RemoteObjectID
    ) throws -> URL {
        let reference = RemoteBlobReference(
            id: object,
            byteCount: 0,
            sha256: String(repeating: "0", count: 64)
        )
        try reference.validate()
        return object.rawValue.split(separator: "/").reduce(rootURL) {
            $0.appending(path: String($1))
        }
    }

    func perform(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw RemoteProviderError.serviceUnavailable("Invalid HTTP response.")
            }
            return (data, response)
        } catch let error as RemoteProviderError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw RemoteProviderError.serviceUnavailable("The request timed out.")
        } catch {
            throw RemoteProviderError.serviceUnavailable("The network request failed.")
        }
    }

    func mappedError(
        _ response: HTTPURLResponse,
        object: RemoteObjectID?
    ) -> RemoteProviderError {
        switch response.statusCode {
        case 401, 403:
            .authenticationRequired
        case 409, 412:
            .conflict
        case 404:
            object.map(RemoteProviderError.objectNotFound)
                ?? .serviceUnavailable("The remote manifest was not found.")
        default:
            .serviceUnavailable("WebDAV returned HTTP \(response.statusCode).")
        }
    }

    static func stream(
        _ data: Data
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let chunkSize = 64 * 1024
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                continuation.yield(data.subdata(in: offset ..< end))
                offset = end
            }
            continuation.finish()
        }
    }
}

private extension HTTPURLResponse {
    var etag: String? {
        value(forHTTPHeaderField: "ETag")
    }
}
