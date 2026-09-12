import Foundation

actor GoogleDriveProvider: RemoteLibraryProvider {
    private let configuration: GoogleDriveConfiguration
    private let session: URLSession
    private let authorization: any GoogleDriveAuthorizing
    private let api: GoogleDriveAPI
    private var resolvedObjectIDs: [RemoteObjectID: String] = [:]

    init(
        configuration: GoogleDriveConfiguration,
        session: URLSession = .shared,
        authorization: any GoogleDriveAuthorizing
    ) {
        self.configuration = configuration
        self.session = session
        self.authorization = authorization
        api = GoogleDriveAPI(authorization: authorization)
    }

    func signOut() async throws {
        resolvedObjectIDs.removeAll()
        try await authorization.signOut()
    }

    func fetchManifest(
        ifNoneMatch revision: String?
    ) async throws -> RemoteManifestResponse {
        var request = try await api.request(
            method: "GET",
            url: api.fileURL(configuration.manifestFileID),
            query: [URLQueryItem(name: "alt", value: "media")]
        )
        if let revision {
            request.setValue(revision, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await perform(request)
        if response.statusCode == 304 {
            return try RemoteManifestResponse(
                manifest: nil,
                revision: RemoteRevision.notModified(
                    response: response.driveETag,
                    request: revision
                ).rawValue
            )
        }
        guard response.statusCode == 200 else {
            throw mappedError(response, object: nil)
        }
        let etag = try RemoteRevision(response.driveETag).rawValue
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
            throw RemoteProviderError.invalidManifest("invalid Google Drive JSON")
        }
        return RemoteManifestResponse(manifest: manifest, revision: etag)
    }

    func read(
        object: RemoteObjectID,
        range: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        let fileID = try await resolveFileID(for: object)
        var request = try await api.request(
            method: "GET",
            url: api.fileURL(fileID),
            query: [URLQueryItem(name: "alt", value: "media")]
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

private extension GoogleDriveProvider {
    func resolveFileID(
        for object: RemoteObjectID
    ) async throws -> String {
        if let cached = resolvedObjectIDs[object] {
            return cached
        }
        let escaped = object.rawValue.replacingOccurrences(of: "'", with: "\\'")
        let query = "appProperties has { key='cadenceObjectID' and value='\(escaped)' } "
            + "and '\(configuration.folderID)' in parents and trashed=false"
        let request = try await api.request(
            method: "GET",
            url: GoogleDriveAPI.filesURL,
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "fields", value: "files(id)"),
                URLQueryItem(name: "pageSize", value: "2"),
            ]
        )
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else {
            throw mappedError(response, object: object)
        }
        let list = try JSONDecoder().decode(GoogleDriveFileList.self, from: data)
        guard list.files.count == 1,
              let fileID = list.files.first?.id
        else {
            throw list.files.isEmpty
                ? RemoteProviderError.objectNotFound(object)
                : RemoteProviderError.conflict
        }
        resolvedObjectIDs[object] = fileID
        return fileID
    }

    func perform(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw RemoteProviderError.serviceUnavailable("Invalid Google Drive response.")
            }
            return (data, response)
        } catch let error as RemoteProviderError {
            throw error
        } catch {
            throw RemoteProviderError.serviceUnavailable("Google Drive request failed.")
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
                ?? .serviceUnavailable("The Drive manifest was not found.")
        default:
            .serviceUnavailable("Google Drive returned HTTP \(response.statusCode).")
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
    var driveETag: String? {
        value(forHTTPHeaderField: "ETag")
    }
}
