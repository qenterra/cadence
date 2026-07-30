import Foundation
import SwiftData

@Model
final class LyricRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var trackID: UUID
    var relativePath: String
    var textEncoding: String
    var parsingStatusRawValue: String
    var timingStatusRawValue: String
    var contentHash: String
    var modifiedAt: Date
    var track: TrackRecord?

    init(
        id: UUID = UUID(),
        relativePath: String,
        textEncoding: String = "UTF-8",
        parsingStatus: StoredLyricParsingStatus = .valid,
        contentHash: String,
        timingStatus: LyricTimingStatus,
        modifiedAt: Date = .now,
        track: TrackRecord
    ) {
        self.id = id
        trackID = track.id
        self.relativePath = relativePath
        self.textEncoding = textEncoding
        parsingStatusRawValue = parsingStatus.rawValue
        timingStatusRawValue = timingStatus.storageRawValue
        self.contentHash = contentHash
        self.modifiedAt = modifiedAt
        self.track = track
    }

    var parsingStatus: StoredLyricParsingStatus {
        get {
            StoredLyricParsingStatus(rawValue: parsingStatusRawValue)
                ?? .malformed
        }
        set {
            parsingStatusRawValue = newValue.rawValue
        }
    }

    var timingStatus: LyricTimingStatus {
        get {
            LyricTimingStatus(storageRawValue: timingStatusRawValue)
                ?? .missing
        }
        set {
            timingStatusRawValue = newValue.storageRawValue
        }
    }
}

enum StoredLyricParsingStatus: String, Codable, Sendable {
    case valid
    case malformed
}

extension LyricTimingStatus {
    init?(storageRawValue: String) {
        switch storageRawValue {
        case "missing":
            self = .missing
        case "unsynchronized":
            self = .unsynchronized
        case "partiallySynchronized":
            self = .partiallySynchronized
        case "synchronized":
            self = .synchronized
        default:
            return nil
        }
    }

    var storageRawValue: String {
        switch self {
        case .missing:
            "missing"
        case .unsynchronized:
            "unsynchronized"
        case .partiallySynchronized:
            "partiallySynchronized"
        case .synchronized:
            "synchronized"
        }
    }
}
