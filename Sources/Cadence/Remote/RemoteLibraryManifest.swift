import Foundation

struct RemoteObjectID: Codable, Hashable, RawRepresentable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

struct RemoteBlobReference: Codable, Equatable, Hashable, Sendable {
    let id: RemoteObjectID
    let byteCount: Int64
    let sha256: String

    init(
        id: RemoteObjectID,
        byteCount: Int64,
        sha256: String
    ) {
        self.id = id
        self.byteCount = byteCount
        self.sha256 = sha256.lowercased()
    }

    func validate() throws {
        guard !id.rawValue.isEmpty,
              !id.rawValue.hasPrefix("/"),
              !id.rawValue.split(separator: "/").contains("..")
        else {
            throw RemoteProviderError.invalidManifest("unsafe object identifier")
        }
        guard byteCount >= 0 else {
            throw RemoteProviderError.invalidManifest("negative object size")
        }
        guard sha256.count == 64,
              sha256.allSatisfy(\.isHexDigit)
        else {
            throw RemoteProviderError.invalidManifest("invalid SHA-256 digest")
        }
    }
}

struct RemoteMediaObject: Codable, Equatable, Hashable, Sendable {
    let id: RemoteObjectID
    let byteCount: Int64
    let sha256: String
    let fileExtension: String

    init(
        id: RemoteObjectID,
        byteCount: Int64,
        sha256: String,
        fileExtension: String
    ) {
        self.id = id
        self.byteCount = byteCount
        self.sha256 = sha256.lowercased()
        self.fileExtension = fileExtension.lowercased()
    }

    var blob: RemoteBlobReference {
        RemoteBlobReference(
            id: id,
            byteCount: byteCount,
            sha256: sha256
        )
    }

    func validate() throws {
        try blob.validate()
        guard !fileExtension.isEmpty,
              fileExtension.allSatisfy({ $0.isLetter || $0.isNumber })
        else {
            throw RemoteProviderError.invalidManifest("invalid media extension")
        }
    }
}

struct RemoteTrackManifestEntry: Codable, Equatable, Hashable, Sendable {
    let trackID: UUID
    let media: RemoteMediaObject
    let artwork: RemoteBlobReference?
    let lyrics: RemoteBlobReference?
}

struct RemoteLibraryManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumTrackCount = 100_000

    let schemaVersion: Int
    let libraryID: UUID
    let generation: Int64
    let tracks: [RemoteTrackManifestEntry]

    init(
        schemaVersion: Int = currentSchemaVersion,
        libraryID: UUID,
        generation: Int64,
        tracks: [RemoteTrackManifestEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.libraryID = libraryID
        self.generation = generation
        self.tracks = tracks
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw RemoteProviderError.invalidManifest("unsupported schema version")
        }
        guard tracks.count <= Self.maximumTrackCount else {
            throw RemoteProviderError.invalidManifest("too many tracks")
        }
        guard generation >= 0 else {
            throw RemoteProviderError.invalidManifest("negative generation")
        }
        guard Set(tracks.map(\.trackID)).count == tracks.count,
              Set(tracks.map(\.media.id)).count == tracks.count
        else {
            throw RemoteProviderError.invalidManifest("duplicate track or media identity")
        }
        for track in tracks {
            try track.media.validate()
            try track.artwork?.validate()
            try track.lyrics?.validate()
        }
    }
}
