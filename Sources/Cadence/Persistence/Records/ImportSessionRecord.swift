import Foundation
import SwiftData

@Model
final class ImportSessionRecord {
    #Index<ImportSessionRecord>(
        [\.stateRawValue],
        [\.createdAt],
        [\.completedAt]
    )

    @Attribute(.unique) var id: UUID
    var sourceDisplayName: String
    var stateRawValue: String
    var createdAt: Date
    var completedAt: Date?
    var importedCount: Int
    var skippedCount: Int
    var failedCount: Int
    var selectedByteCount: Int64
    var manifestVersion: Int

    init(
        id: UUID = UUID(),
        sourceDisplayName: String,
        state: ImportSessionState,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        importedCount: Int = 0,
        skippedCount: Int = 0,
        failedCount: Int = 0,
        selectedByteCount: Int64 = 0,
        manifestVersion: Int = 1
    ) {
        self.id = id
        self.sourceDisplayName = sourceDisplayName
        stateRawValue = state.rawValue
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.selectedByteCount = selectedByteCount
        self.manifestVersion = manifestVersion
    }

    var state: ImportSessionState {
        get {
            ImportSessionState(rawValue: stateRawValue) ?? .rollbackRequired
        }
        set {
            stateRawValue = newValue.rawValue
        }
    }
}

enum ImportSessionState: String, Codable, CaseIterable, Sendable {
    case prepared
    case copied
    case filesCommitted
    case storeCommitted
    case complete
    case rollbackRequired
}
