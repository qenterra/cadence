import Foundation

struct RemoteRevision: Equatable, Sendable {
    let rawValue: String

    init(_ candidate: String?) throws {
        guard let candidate else {
            throw RemoteProviderError.invalidRevision
        }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RemoteProviderError.invalidRevision
        }
        rawValue = trimmed
    }

    static func notModified(
        response: String?,
        request: String?
    ) throws -> RemoteRevision {
        if let response,
           !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try RemoteRevision(response)
        }
        return try RemoteRevision(request)
    }
}

struct RemoteManifestResponse: Equatable, Sendable {
    let manifest: RemoteLibraryManifest?
    let revision: String
}

/// Read-only access to one remote Cadence library.
///
/// Manifest fetches preserve conditional revisions; media reads return byte streams.
protocol RemoteLibraryProvider: Sendable {
    func fetchManifest(ifNoneMatch revision: String?) async throws -> RemoteManifestResponse
    func read(
        object: RemoteObjectID,
        range: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error>
}
