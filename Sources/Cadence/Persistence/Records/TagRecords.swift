import Foundation
import SwiftData

@Model
final class TagRecord {
    #Index<TagRecord>([\.normalizedPath], [\.groupPath])

    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var normalizedPath: String
    var displayPath: String
    var groupPath: String?

    init(
        id: UUID = UUID(),
        displayPath: String,
        groupPath: String? = nil
    ) {
        self.id = id
        self.displayPath = displayPath
        normalizedPath = SearchNormalizer.normalize(displayPath)
        self.groupPath = groupPath
    }
}

@Model
final class TagAssignmentRecord {
    #Index<TagAssignmentRecord>(
        [\.targetID],
        [\.tagID],
        [\.targetID, \.tagID]
    )

    @Attribute(.unique) var id: UUID
    var targetKindRawValue: String
    var targetID: UUID
    var tagID: UUID
    var assignedAt: Date

    init(
        id: UUID = UUID(),
        targetKind: TagTargetKind,
        targetID: UUID,
        tagID: UUID,
        assignedAt: Date = .now
    ) {
        self.id = id
        targetKindRawValue = targetKind.rawValue
        self.targetID = targetID
        self.tagID = tagID
        self.assignedAt = assignedAt
    }

    var targetKind: TagTargetKind {
        get {
            TagTargetKind(rawValue: targetKindRawValue) ?? .track
        }
        set {
            targetKindRawValue = newValue.rawValue
        }
    }
}

@Model
final class TagExclusionRecord {
    #Index<TagExclusionRecord>(
        [\.trackID],
        [\.tagID],
        [\.trackID, \.tagID]
    )

    @Attribute(.unique) var id: UUID
    var trackID: UUID
    var tagID: UUID
    var excludedAt: Date

    init(
        id: UUID = UUID(),
        trackID: UUID,
        tagID: UUID,
        excludedAt: Date = .now
    ) {
        self.id = id
        self.trackID = trackID
        self.tagID = tagID
        self.excludedAt = excludedAt
    }
}

enum TagTargetKind: String, Codable, Sendable {
    case album
    case track
}
