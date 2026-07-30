import Foundation

struct ManagedTrashManifest: Codable, Sendable {
    static let currentVersion = 2

    let version: Int
    let operationID: UUID
    let targetKind: TrashTargetKind
    let createdAt: Date
    let artists: [TrashArtistSnapshot]
    let albums: [TrashAlbumSnapshot]
    let tracks: [TrashTrackSnapshot]
    let lyrics: [TrashLyricSnapshot]
    let artworks: [TrashArtworkSnapshot]
    let tagAssignments: [TrashTagAssignmentSnapshot]
    let tagExclusions: [TrashTagExclusionSnapshot]
    let playlistEntries: [TrashPlaylistEntrySnapshot]?
    let originalRelativePaths: [String]
}

struct TrashPlaylistEntrySnapshot: Codable, Sendable {
    let id: UUID
    let playlistID: UUID
    let trackID: UUID
    let position: Int
    let dateAdded: Date
}

struct TrashArtistSnapshot: Codable, Sendable {
    let id: UUID
    let name: String
    let isFavorite: Bool
    let favoriteDate: Date?
    let customArtworkID: UUID?
}

struct TrashAlbumSnapshot: Codable, Sendable {
    let id: UUID
    let title: String
    let artistID: UUID?
    let year: Int?
    let dateAdded: Date
    let isFavorite: Bool
    let favoriteDate: Date?
    let customArtworkID: UUID?
}

struct TrashTrackSnapshot: Codable, Sendable {
    let id: UUID
    let originalFilename: String
    let title: String
    let trackNumber: Int?
    let discNumber: Int?
    let duration: TimeInterval
    let sourceFrameCount: Int64?
    let dateAdded: Date
    let lastPlayedAt: Date?
    let playCount: Int
    let skipCount: Int
    let isFavorite: Bool
    let codec: String
    let container: String
    let sampleRate: Double
    let channelCount: Int
    let bitrate: Int?
    let bitDepth: Int?
    let spatialFormat: StoredSpatialFormat
    let contentHash: String
    let relativeMediaPath: String
    let sourceMetadata: Data?
    let importSessionID: UUID
    let customArtworkID: UUID?
    let replayGainTrackGain: Double?
    let replayGainTrackPeak: Double?
    let artistID: UUID?
    let albumID: UUID?
}

struct TrashLyricSnapshot: Codable, Sendable {
    let id: UUID
    let trackID: UUID
    let relativePath: String
    let textEncoding: String
    let parsingStatus: StoredLyricParsingStatus
    let timingStatusRawValue: String
    let contentHash: String
    let modifiedAt: Date
}

struct TrashArtworkSnapshot: Codable, Sendable {
    let id: UUID
    let ownerKind: ArtworkOwnerKind
    let ownerID: UUID
    let relativeOriginalPath: String
    let relativeThumbnailPath: String?
    let format: String
    let pixelWidth: Int
    let pixelHeight: Int
    let cropScale: Double
    let normalizedOffsetX: Double
    let normalizedOffsetY: Double
    let contentHash: String
    let revision: Int
}

struct TrashTagAssignmentSnapshot: Codable, Sendable {
    let id: UUID
    let targetKind: TagTargetKind
    let targetID: UUID
    let tagID: UUID
    let assignedAt: Date
}

struct TrashTagExclusionSnapshot: Codable, Sendable {
    let id: UUID
    let trackID: UUID
    let tagID: UUID
    let excludedAt: Date
}
