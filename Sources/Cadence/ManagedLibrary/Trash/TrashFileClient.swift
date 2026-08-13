import Foundation

/// File-system boundary for Trash transactions. Keeping it injectable lets
/// recovery behavior be verified without relying on timing-sensitive disk faults.
struct TrashFileClient: Sendable {
    let fileExists: @Sendable (URL) -> Bool
    let createDirectory: @Sendable (URL) throws -> Void
    let moveItem: @Sendable (URL, URL) throws -> Void
    let removeItem: @Sendable (URL) throws -> Void

    static let live = TrashFileClient(
        fileExists: { FileManager.default.fileExists(atPath: $0.path) },
        createDirectory: {
            try FileManager.default.createDirectory(
                at: $0,
                withIntermediateDirectories: true
            )
        },
        moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
        removeItem: { try FileManager.default.removeItem(at: $0) }
    )
}

enum LibraryTrashTransactionPhase: String, Equatable, Sendable {
    case writeManifest
    case moveFiles
    case commitCatalog
    case restoreFiles
    case restoreCatalog
    case cleanup
    case reconcile
}

/// Carries both the original transaction failure and every failed compensation.
/// The recovery directory is intentionally retained whenever manual or launch-time
/// repair is still required.
struct LibraryTrashTransactionError: Error, LocalizedError, Sendable {
    let operationID: UUID
    let phase: LibraryTrashTransactionPhase
    let primaryFailure: String
    let compensationFailures: [String]
    let recoveryDirectory: URL

    var errorDescription: String? {
        var message = "Trash operation failed during \(phase.rawValue): "
            + primaryFailure
        if !compensationFailures.isEmpty {
            message += ". Recovery also failed: "
                + compensationFailures.joined(separator: "; ")
        }
        return message
    }
}
