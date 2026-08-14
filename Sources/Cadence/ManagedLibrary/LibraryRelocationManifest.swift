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
        return String(localized: "\(completedCount) of \(totalCount)")
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
