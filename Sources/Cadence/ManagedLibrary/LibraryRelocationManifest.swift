import Foundation

enum LibraryRelocationError: Error, Equatable, LocalizedError, Sendable {
    case sourceUnavailable(URL)
    case sameLocation
    case destinationConflict(URL)
    case verificationFailed(String)
    case invalidDestination(String)

    var errorDescription: String? {
        switch self {
        case let .sourceUnavailable(url):
            "The active library is unavailable at \(url.path)."
        case .sameLocation:
            "The library is already stored in this folder."
        case let .destinationConflict(url):
            "A Cadence.library package already exists at \(url.path)."
        case let .verificationFailed(path):
            "The copied file failed verification: \(path)."
        case let .invalidDestination(message):
            "The copied library could not be opened: \(message)"
        }
    }
}

enum LibraryRelocationPhase: String, Codable, CaseIterable, Sendable {
    case preflight
    case copying
    case verifying
    case finalized
    case destinationValidated
    case switched
    case sourceCleanup
    case complete
}

struct RelocationFile: Codable, Equatable, Sendable {
    let relativePath: String
    let byteCount: Int64
    let sha256: String
}

struct LibraryRelocationManifest: Codable, Equatable, Sendable {
    let operationID: UUID
    let libraryIdentity: LibraryIdentity
    let sourcePackagePath: String
    let destinationPackagePath: String
    var phase: LibraryRelocationPhase
    var files: [RelocationFile]
}

struct LibraryRelocationProgress: Equatable, Sendable {
    let phase: LibraryRelocationPhase
    let completedCount: Int
    let totalCount: Int

    var fractionCompleted: Double? {
        guard totalCount > 0 else { return nil }
        return min(Double(completedCount) / Double(totalCount), 1)
    }

    var label: String {
        guard totalCount > 0 else { return phase.title }
        return String(localized: "\(completedCount) of \(totalCount)")
    }
}

enum LibraryRelocationFinishError: Error, Equatable, LocalizedError, Sendable {
    case manifestPersistenceFailed(
        phase: LibraryRelocationPhase,
        manifestPath: String
    )
    case sourceCleanupFailed(packagePath: String)
    case completionRecordCleanupFailed(manifestPath: String)

    var errorDescription: String? {
        switch self {
        case let .manifestPersistenceFailed(phase, manifestPath):
            if phase == .complete {
                "The library was moved, but Cadence could not verify the completion "
                    + "record at \(manifestPath)."
            } else {
                "The library is active in its new location, but Cadence could not verify the "
                    + "\(phase.title.lowercased()) recovery record at \(manifestPath). "
                    + "The original library was left in place."
            }
        case let .sourceCleanupFailed(packagePath):
            "The library is active in its new location, but the original package at "
                + "\(packagePath) could not be moved to Trash."
        case let .completionRecordCleanupFailed(manifestPath):
            "The library was moved, but Cadence could not remove the completed recovery "
                + "record at \(manifestPath)."
        }
    }
}

extension LibraryRelocationPhase {
    var title: String {
        switch self {
        case .preflight: String(localized: "Checking Destination")
        case .copying: String(localized: "Copying Library")
        case .verifying: String(localized: "Verifying Library")
        case .finalized: String(localized: "Finalizing Package")
        case .destinationValidated: String(localized: "Opening Destination")
        case .switched: String(localized: "Switching Library")
        case .sourceCleanup: String(localized: "Cleaning Up Source")
        case .complete: String(localized: "Library Moved")
        }
    }
}
