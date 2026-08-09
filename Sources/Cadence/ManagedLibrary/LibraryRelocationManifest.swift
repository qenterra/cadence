import Foundation

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
        return "\(completedCount) of \(totalCount)"
    }
}

extension LibraryRelocationPhase {
    var title: String {
        switch self {
        case .preflight: "Checking Destination"
        case .copying: "Copying Library"
        case .verifying: "Verifying Library"
        case .finalized: "Finalizing Package"
        case .destinationValidated: "Opening Destination"
        case .switched: "Switching Library"
        case .sourceCleanup: "Cleaning Up Source"
        case .complete: "Library Moved"
        }
    }
}
