import Foundation

actor GoogleDriveProvider: RemoteLibraryProvider {
    private struct PendingUpload: Sendable {
        let driveFileID: String
        let digest: String
    }

    private let configuration: GoogleDriveConfiguration
    private let session: URLSession
    private let authorization: any GoogleDriveAuthorizing
    private let api: GoogleDriveAPI
    private var resolvedObjectIDs: [RemoteObjectID: String] = [:]
    private var pendingUploads: [UUID: PendingUpload] = [:]

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

    func restoreSession() async throws {
        try await authorization.restoreSession()
    }

    func signOut() async throws {
        resolvedObjectIDs.removeAll()
        pendingUploads.removeAll()
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

    func uploadTemporary(
        object: RemoteObjectID,
        bytes: AsyncThrowingStream<Data, Error>
    ) async throws -> RemoteUpload {
        try RemoteBlobReference(
            id: object,
            byteCount: 0,
            sha256: String(repeating: "0", count: 64)
        ).validate()
        let upload = RemoteUpload(id: UUID(), object: object)
        let localURL = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Drive-\(upload.id.uuidString).upload",
            directoryHint: .notDirectory
        )
        defer { try? FileManager.default.removeItem(at: localURL) }
        try await write(bytes, to: localURL)
        let digest = try await ContentHasher().sha256(of: localURL)

        let sessionURL = try await beginUpload(object: object, uploadID: upload.id)
        let fileID = try await transfer(
            localURL: localURL,
            sessionURL: sessionURL,
            object: object
        )
        pendingUploads[upload.id] = PendingUpload(
            driveFileID: fileID,
            digest: digest
        )
        return upload
    }

    func finalize(
        _ upload: RemoteUpload,
        expectedSHA256: String
    ) async throws {
        guard let pending = pendingUploads[upload.id] else {
            throw RemoteProviderError.objectNotFound(upload.object)
        }
        guard pending.digest == expectedSHA256.lowercased() else {
            throw RemoteProviderError.integrityMismatch
        }
        var request = try await api.request(
            method: "PATCH",
            url: api.fileURL(pending.driveFileID),
            query: [URLQueryItem(name: "fields", value: "id")]
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": upload.object.rawValue,
            "appProperties": [
                "cadenceObjectID": upload.object.rawValue,
                "cadenceSHA256": expectedSHA256.lowercased(),
            ],
        ])
        let (_, response) = try await perform(request)
        guard Self.successStatuses.contains(response.statusCode) else {
            throw mappedError(response, object: upload.object)
        }
        resolvedObjectIDs[upload.object] = pending.driveFileID
        pendingUploads[upload.id] = nil
    }

    func commitManifest(
        _ manifest: RemoteLibraryManifest,
        matching revision: String?
    ) async throws -> String {
        try manifest.validate()
        var request = try await api.request(
            method: "PATCH",
            url: api.fileURL(configuration.manifestFileID, upload: true),
            query: [URLQueryItem(name: "uploadType", value: "media")]
        )
        request.httpBody = try JSONEncoder().encode(manifest)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let revision {
            request.setValue(revision, forHTTPHeaderField: "If-Match")
        } else {
            request.setValue("*", forHTTPHeaderField: "If-None-Match")
        }
        let (_, response) = try await perform(request)
        guard Self.successStatuses.contains(response.statusCode) else {
            throw mappedError(response, object: nil)
        }
        return try RemoteRevision(response.driveETag).rawValue
    }

    func delete(
        object: RemoteObjectID
    ) async throws {
        let fileID = try await resolveFileID(for: object)
        let request = try await api.request(
            method: "DELETE",
            url: api.fileURL(fileID)
        )
        let (_, response) = try await perform(request)
        guard Self.successStatuses.contains(response.statusCode)
            || response.statusCode == 404
        else {
            throw mappedError(response, object: object)
        }
        resolvedObjectIDs[object] = nil
    }
}

private extension GoogleDriveProvider {
    static let successStatuses = 200 ... 299

    func beginUpload(
        object: RemoteObjectID,
        uploadID: UUID
    ) async throws -> URL {
        var request = try await api.request(
            method: "POST",
            url: GoogleDriveAPI.uploadFilesURL,
            query: [
                URLQueryItem(name: "uploadType", value: "resumable"),
                URLQueryItem(name: "fields", value: "id"),
            ]
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "application/octet-stream",
            forHTTPHeaderField: "X-Upload-Content-Type"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": ".cadence-stage-\(uploadID.uuidString)",
            "parents": [configuration.folderID],
            "appProperties": ["cadencePendingObjectID": object.rawValue],
        ])
        let (_, response) = try await perform(request)
        guard Self.successStatuses.contains(response.statusCode),
              let location = response.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location)
        else {
            throw mappedError(response, object: object)
        }
        return url
    }

    func transfer(
        localURL: URL,
        sessionURL: URL,
        object: RemoteObjectID
    ) async throws -> String {
        var request = try await api.request(method: "PUT", url: sessionURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await performUpload(request, fromFile: localURL)
        guard Self.successStatuses.contains(response.statusCode) else {
            throw mappedError(response, object: object)
        }
        return try JSONDecoder().decode(GoogleDriveFile.self, from: data).id
    }

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

    func write(
        _ bytes: AsyncThrowingStream<Data, Error>,
        to url: URL
    ) async throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw RemoteProviderError.serviceUnavailable(
                "The upload staging file could not be created."
            )
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            for try await chunk in bytes {
                try Task.checkCancellation()
                try handle.write(contentsOf: chunk)
            }
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
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

    func performUpload(
        _ request: URLRequest,
        fromFile url: URL
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.upload(for: request, fromFile: url)
            guard let response = response as? HTTPURLResponse else {
                throw RemoteProviderError.serviceUnavailable("Invalid Google Drive response.")
            }
            return (data, response)
        } catch let error as RemoteProviderError {
            throw error
        } catch {
            throw RemoteProviderError.serviceUnavailable("Google Drive upload failed.")
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
