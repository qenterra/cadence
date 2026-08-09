import Foundation

struct RemoteCacheEntry: Codable, Equatable, Sendable {
    let object: RemoteMediaObject
    let relativePath: String
    var lastAccessedAt: Date
}

struct RemoteCacheIndex: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var entries: [RemoteCacheEntry] = []

    subscript(id: RemoteObjectID) -> RemoteCacheEntry? {
        get { entries.first { $0.object.id == id } }
        set {
            entries.removeAll { $0.object.id == id }
            if let newValue {
                entries.append(newValue)
            }
        }
    }
}
