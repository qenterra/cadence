import Foundation

enum CloudLibraryEntityKind: String, Codable, CaseIterable, Sendable {
    case artist
    case album
    case track
    case lyric
    case playlist
    case playlistEntry
    case smartCollection
    case tag
    case tagAssignment
    case tagExclusion
    case artwork
    case artistCredit
}

struct CloudLibraryEntity: Codable, Equatable, Sendable {
    let kind: CloudLibraryEntityKind
    let id: UUID
    let payload: Data
}

struct CloudLibraryRecord: Codable, Equatable, Sendable {
    let libraryID: UUID
    let entityKind: CloudLibraryEntityKind
    let entityID: UUID
    var payload: Data
    var userModificationDate: Date
    var deviceID: UUID
    var isTombstone: Bool
    var lastKnownRecordData: Data?

    var recordName: String {
        "\(libraryID.uuidString).\(entityKind.rawValue).\(entityID.uuidString)"
    }

    static func live(
        libraryID: UUID,
        entity: CloudLibraryEntity,
        modifiedAt: Date,
        deviceID: UUID
    ) -> CloudLibraryRecord {
        CloudLibraryRecord(
            libraryID: libraryID,
            entityKind: entity.kind,
            entityID: entity.id,
            payload: entity.payload,
            userModificationDate: modifiedAt,
            deviceID: deviceID,
            isTombstone: false
        )
    }

    static func tombstone(
        replacing record: CloudLibraryRecord,
        modifiedAt: Date,
        deviceID: UUID
    ) -> CloudLibraryRecord {
        CloudLibraryRecord(
            libraryID: record.libraryID,
            entityKind: record.entityKind,
            entityID: record.entityID,
            payload: Data(),
            userModificationDate: modifiedAt,
            deviceID: deviceID,
            isTombstone: true,
            lastKnownRecordData: record.lastKnownRecordData
        )
    }
}

enum CloudLibraryConflictResolver {
    static func preferred(
        local: CloudLibraryRecord,
        remote: CloudLibraryRecord
    ) -> CloudLibraryRecord {
        guard local.userModificationDate == remote.userModificationDate else {
            return local.userModificationDate > remote.userModificationDate
                ? local
                : remote
        }
        if local.isTombstone != remote.isTombstone {
            return local.isTombstone ? local : remote
        }
        return local.deviceID.uuidString > remote.deviceID.uuidString
            ? local
            : remote
    }
}

struct ArtistCloudPayload: Codable, Sendable {
    let name: String
    let isFavorite: Bool
    let favoriteDate: Date?
    let trackCount: Int
    let albumCount: Int
    let customArtworkID: UUID?
}

struct AlbumCloudPayload: Codable, Sendable {
    let title: String
    let artistID: UUID?
    let year: Int?
    let isFavorite: Bool
    let favoriteDate: Date?
    let trackCount: Int
    let totalDuration: TimeInterval
    let customArtworkID: UUID?
}

struct TrackCloudPayload: Codable, Sendable {
    let originalFilename: String
    let title: String
    let duration: TimeInterval
    let codec: String
    let container: String
    let sampleRate: Double
    let channelCount: Int
    let bitDepth: Int?
    let bitrate: Int?
    let contentHash: String
    let relativeMediaPath: String
    let importSessionID: UUID
    let artistID: UUID?
    let albumID: UUID?
    let trackNumber: Int?
    let discNumber: Int?
    let sourceFrameCount: Int64?
    let lastPlayedAt: Date?
    let skipCount: Int
    let isFavorite: Bool
    let spatialFormatRawValue: String
    let sourceMetadata: Data?
    let customArtworkID: UUID?
    let replayGainTrackGain: Double?
    let replayGainTrackPeak: Double?
}

struct LyricCloudPayload: Codable, Sendable {
    let trackID: UUID
    let relativePath: String
    let textEncoding: String
    let parsingStatusRawValue: String
    let timingStatusRawValue: String
    let contentHash: String
    let modifiedAt: Date
}

struct PlaylistCloudPayload: Codable, Sendable {
    let name: String
    let createdAt: Date
    let modifiedAt: Date
    let customArtworkID: UUID?
}

struct PlaylistEntryCloudPayload: Codable, Sendable {
    let playlistID: UUID
    let trackID: UUID
    let position: Int
}

struct SmartCollectionCloudPayload: Codable, Sendable {
    let name: String
    let ruleData: Data
    let sortDescriptorRawValue: String
    let playbackPreferenceRawValue: String
    let modifiedAt: Date
}

struct TagCloudPayload: Codable, Sendable {
    let displayPath: String
    let groupPath: String?
}

struct TagAssignmentCloudPayload: Codable, Sendable {
    let targetKindRawValue: String
    let targetID: UUID
    let tagID: UUID
    let assignedAt: Date
}

struct TagExclusionCloudPayload: Codable, Sendable {
    let trackID: UUID
    let tagID: UUID
    let excludedAt: Date
}

struct ArtworkCloudPayload: Codable, Sendable {
    let ownerKindRawValue: String
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

struct ArtistCreditCloudPayload: Codable, Sendable {
    let trackID: UUID
    let artistID: UUID
    let position: Int
    let displayArtistName: String
}
