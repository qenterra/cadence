import Foundation

struct GoogleDriveConfiguration: Codable, Equatable, Sendable {
    let folderID: String
    let manifestFileID: String
}

struct GoogleDriveFileList: Decodable, Sendable {
    let files: [GoogleDriveFile]
}

struct GoogleDriveFile: Decodable, Sendable {
    let id: String
}

struct GoogleDriveAPI: Sendable {
    static let filesURL = URL(
        string: "https://www.googleapis.com/drive/v3/files"
    )!
    static let uploadFilesURL = URL(
        string: "https://www.googleapis.com/upload/drive/v3/files"
    )!

    let authorization: any GoogleDriveAuthorizing

    func request(
        method: String,
        url: URL,
        query: [URLQueryItem] = []
    ) async throws -> URLRequest {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            throw RemoteProviderError.serviceUnavailable("Invalid Google Drive URL.")
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let resolvedURL = components.url else {
            throw RemoteProviderError.serviceUnavailable("Invalid Google Drive query.")
        }
        var request = URLRequest(url: resolvedURL)
        request.httpMethod = method
        request.timeoutInterval = 30
        try await request.setValue(
            "Bearer \(authorization.accessToken())",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("Cadence/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    func fileURL(
        _ id: String,
        upload: Bool = false
    ) -> URL {
        (upload ? Self.uploadFilesURL : Self.filesURL)
            .appending(path: id, directoryHint: .notDirectory)
    }
}
