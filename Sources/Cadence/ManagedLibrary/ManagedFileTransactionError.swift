import Foundation

enum ManagedFileTransactionSubsystem: String, Sendable {
    case artwork
    case lyrics
}

/// Reports the original managed-file failure together with every failed
/// compensation. A successful compensation keeps the original domain error.
struct ManagedFileTransactionError: Error, LocalizedError, Sendable {
    let subsystem: ManagedFileTransactionSubsystem
    let operationID: UUID
    let primaryFailure: String
    let compensationFailures: [String]
    let recoveryDirectory: URL

    var errorDescription: String? {
        "\(subsystem.rawValue.capitalized) update failed: \(primaryFailure). "
            + "Recovery also failed: "
            + compensationFailures.joined(separator: "; ")
            + ". Operation \(operationID.uuidString); recovery data: "
            + recoveryDirectory.path(percentEncoded: false)
    }
}

func managedFileError(
    preserving primary: any Error,
    subsystem: ManagedFileTransactionSubsystem,
    operationID: UUID,
    compensationFailures: [String],
    recoveryDirectory: URL
) -> any Error {
    guard !compensationFailures.isEmpty else {
        return primary
    }
    return ManagedFileTransactionError(
        subsystem: subsystem,
        operationID: operationID,
        primaryFailure: primary.localizedDescription,
        compensationFailures: compensationFailures,
        recoveryDirectory: recoveryDirectory
    )
}
