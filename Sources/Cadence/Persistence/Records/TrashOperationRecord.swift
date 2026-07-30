import Foundation
import SwiftData

@Model
final class TrashOperationRecord {
    #Index<TrashOperationRecord>([\.createdAt], [\.completedAt])

    @Attribute(.unique) var id: UUID
    var targetKindRawValue: String
    var targetIDsData: Data
    var originalRelativePathsData: Data
    var createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        targetKind: TrashTargetKind,
        targetIDsData: Data,
        originalRelativePathsData: Data,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        targetKindRawValue = targetKind.rawValue
        self.targetIDsData = targetIDsData
        self.originalRelativePathsData = originalRelativePathsData
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    var targetKind: TrashTargetKind {
        get {
            TrashTargetKind(rawValue: targetKindRawValue) ?? .track
        }
        set {
            targetKindRawValue = newValue.rawValue
        }
    }
}

enum TrashTargetKind: String, Codable, Hashable, Sendable {
    case artist
    case album
    case track
}
