import Foundation

struct RemoteManifestResponse: Equatable, Sendable {
    let manifest: RemoteLibraryManifest?
    let revision: String
}

struct RemoteUpload: Equatable, Hashable, Sendable {
    let id: UUID
    let object: RemoteObjectID
}

protocol RemoteLibraryProvider: Sendable {
    func restoreSession() async throws
    func fetchManifest(ifNoneMatch revision: String?) async throws -> RemoteManifestResponse
    func read(
        object: RemoteObjectID,
        range: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error>
    func uploadTemporary(
        object: RemoteObjectID,
        bytes: AsyncThrowingStream<Data, Error>
    ) async throws -> RemoteUpload
    func finalize(
        _ upload: RemoteUpload,
        expectedSHA256: String
    ) async throws
    func commitManifest(
        _ manifest: RemoteLibraryManifest,
        matching revision: String?
    ) async throws -> String
    func delete(object: RemoteObjectID) async throws
}
