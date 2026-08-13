import Foundation
import SwiftData

struct ManagedTrashRecoveryResult: Equatable, Sendable {
    let rolledBackOperationIDs: [UUID]
    let reconstructedOperationIDs: [UUID]
    let cleanedOperationIDs: [UUID]

    static let empty = ManagedTrashRecoveryResult(
        rolledBackOperationIDs: [],
        reconstructedOperationIDs: [],
        cleanedOperationIDs: []
    )
}

extension LibraryRepository {
    /// Reconciles durable Trash manifests against the catalog before the library
    /// is exposed to the UI. Ambiguous or damaged evidence fails closed.
    func reconcileTrash(
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient = .live
    ) throws -> ManagedTrashRecoveryResult {
        let store = ManagedTrashManifestStore(location: location)
        let records = try modelContext.fetch(
            FetchDescriptor<TrashOperationRecord>()
        )
        let recordsByID = Dictionary(
            uniqueKeysWithValues: records.map { ($0.id, $0) }
        )
        let manifestIDs = try store.operationIDs()
        let manifestIDSet = Set(manifestIDs)

        if let orphanedRecord = records.first(
            where: { !manifestIDSet.contains($0.id) }
        ) {
            throw recoveryError(
                operationID: orphanedRecord.id,
                message: "The catalog has no matching Trash manifest.",
                location: location
            )
        }

        var rolledBack: [UUID] = []
        var reconstructed: [UUID] = []
        var cleaned: [UUID] = []
        for operationID in manifestIDs.sorted(
            by: { $0.uuidString < $1.uuidString }
        ) {
            let outcome = try reconcileTrashManifest(
                operationID: operationID,
                isRecorded: recordsByID[operationID] != nil,
                store: store,
                location: location,
                fileClient: fileClient
            )
            switch outcome {
            case .unchanged:
                break
            case .rolledBack:
                rolledBack.append(operationID)
            case .reconstructed:
                reconstructed.append(operationID)
            case .cleaned:
                cleaned.append(operationID)
            }
        }
        return ManagedTrashRecoveryResult(
            rolledBackOperationIDs: rolledBack,
            reconstructedOperationIDs: reconstructed,
            cleanedOperationIDs: cleaned
        )
    }
}

private struct TrashRecoveryFileState {
    let pathCount: Int
    let originalCount: Int
    let trashedCount: Int

    var hasOriginalFiles: Bool {
        originalCount > 0
    }

    var hasTrashedFiles: Bool {
        trashedCount > 0
    }

    var isCompleteAtOriginal: Bool {
        originalCount == pathCount
    }

    var isCompleteInTrash: Bool {
        trashedCount == pathCount
    }
}

private enum TrashReconciliationOutcome {
    case unchanged
    case rolledBack
    case reconstructed
    case cleaned
}

private extension LibraryRepository {
    func reconcileTrashManifest(
        operationID: UUID,
        isRecorded: Bool,
        store: ManagedTrashManifestStore,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient
    ) throws -> TrashReconciliationOutcome {
        let manifest = try store.read(operationID: operationID)
        let state = try recoveryFileState(
            manifest: manifest,
            location: location,
            fileClient: fileClient
        )
        try validateRecoveryFileState(
            state,
            operationID: operationID,
            isRecorded: isRecorded,
            location: location
        )
        if isRecorded {
            return .unchanged
        }
        let targetExists = try trashTargetExists(manifest)
        return try reconcileUnrecordedTrash(
            manifest: manifest,
            state: state,
            targetExists: targetExists,
            location: location,
            fileClient: fileClient
        )
    }

    func reconcileUnrecordedTrash(
        manifest: ManagedTrashManifest,
        state: TrashRecoveryFileState,
        targetExists: Bool,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient
    ) throws -> TrashReconciliationOutcome {
        let operationID = manifest.operationID
        if state.isCompleteInTrash, !targetExists {
            try reconstructTrashOperation(from: manifest)
            return .reconstructed
        }
        var outcome = TrashReconciliationOutcome.cleaned
        if state.hasTrashedFiles {
            guard targetExists else {
                throw recoveryError(
                    operationID: operationID,
                    message: "Trash recovery cannot determine a safe catalog state.",
                    location: location
                )
            }
            try rollBackUncommittedTrash(
                manifest: manifest,
                location: location,
                fileClient: fileClient
            )
            outcome = .rolledBack
        } else if !targetExists, state.pathCount == 0 {
            try reconstructTrashOperation(from: manifest)
            return .reconstructed
        } else {
            guard targetExists, state.isCompleteAtOriginal else {
                throw recoveryError(
                    operationID: operationID,
                    message: "Trash recovery cannot determine a safe catalog state.",
                    location: location
                )
            }
        }
        try cleanupReconciledTrash(
            operationID: operationID,
            location: location,
            fileClient: fileClient
        )
        return outcome
    }

    func validateRecoveryFileState(
        _ state: TrashRecoveryFileState,
        operationID: UUID,
        isRecorded: Bool,
        location: ManagedLibraryLocation
    ) throws {
        let hasMissingFiles = state.originalCount + state.trashedCount
            != state.pathCount
        guard !hasMissingFiles else {
            throw recoveryError(
                operationID: operationID,
                message: "A managed file is missing from both the library and Trash.",
                location: location
            )
        }
        guard !isRecorded || state.isCompleteInTrash else {
            throw recoveryError(
                operationID: operationID,
                message: "A committed Trash operation has files outside Trash.",
                location: location
            )
        }
    }

    func cleanupReconciledTrash(
        operationID: UUID,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient
    ) throws {
        do {
            try removeTrashOperationDirectory(
                operationID: operationID,
                location: location,
                fileClient: fileClient
            )
        } catch {
            throw LibraryTrashTransactionError(
                operationID: operationID,
                phase: .reconcile,
                primaryFailure: error.localizedDescription,
                compensationFailures: [],
                recoveryDirectory: trashOperationDirectory(
                    operationID: operationID,
                    location: location
                )
            )
        }
    }

    func recoveryFileState(
        manifest: ManagedTrashManifest,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient
    ) throws -> TrashRecoveryFileState {
        var originalCount = 0
        var trashedCount = 0
        for path in manifest.originalRelativePaths {
            let original = try location.resolve(relativePath: path)
            let trashed = try location.resolve(
                relativePath: "Trash/\(manifest.operationID)/\(path)"
            )
            let originalExists = fileClient.fileExists(original)
            let trashedExists = fileClient.fileExists(trashed)
            guard !(originalExists && trashedExists) else {
                throw recoveryError(
                    operationID: manifest.operationID,
                    message: "A managed file exists in both the library and Trash.",
                    location: location
                )
            }
            originalCount += originalExists ? 1 : 0
            trashedCount += trashedExists ? 1 : 0
        }
        return TrashRecoveryFileState(
            pathCount: manifest.originalRelativePaths.count,
            originalCount: originalCount,
            trashedCount: trashedCount
        )
    }

    func trashTargetExists(_ manifest: ManagedTrashManifest) throws -> Bool {
        if !manifest.tracks.isEmpty {
            let ids = manifest.tracks.map(\.id)
            return try !modelContext.fetch(
                FetchDescriptor<TrackRecord>(
                    predicate: #Predicate { ids.contains($0.id) }
                )
            ).isEmpty
        }
        guard manifest.targetKind == .artist,
              let targetID = manifest.targetID
        else {
            return false
        }
        return try !modelContext.fetch(
            FetchDescriptor<ArtistRecord>(
                predicate: #Predicate { $0.id == targetID }
            )
        ).isEmpty
    }

    func reconstructTrashOperation(
        from manifest: ManagedTrashManifest
    ) throws {
        let encoder = JSONEncoder()
        var targetIDs = Set(manifest.tracks.map(\.id))
        if manifest.targetKind == .artist, let targetID = manifest.targetID {
            targetIDs.insert(targetID)
        }
        try modelContext.insert(
            TrashOperationRecord(
                id: manifest.operationID,
                targetKind: manifest.targetKind,
                targetIDsData: encoder.encode(Array(targetIDs)),
                originalRelativePathsData: encoder.encode(
                    manifest.originalRelativePaths
                ),
                createdAt: manifest.createdAt,
                completedAt: .now
            )
        )
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func rollBackUncommittedTrash(
        manifest: ManagedTrashManifest,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient
    ) throws {
        var failures: [String] = []
        for path in manifest.originalRelativePaths.reversed() {
            do {
                let original = try location.resolve(relativePath: path)
                let trashed = try location.resolve(
                    relativePath: "Trash/\(manifest.operationID)/\(path)"
                )
                guard fileClient.fileExists(trashed) else {
                    continue
                }
                guard !fileClient.fileExists(original) else {
                    throw LibraryTrashError.destinationConflict
                }
                try fileClient.createDirectory(
                    original.deletingLastPathComponent()
                )
                try fileClient.moveItem(trashed, original)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        guard failures.isEmpty else {
            throw LibraryTrashTransactionError(
                operationID: manifest.operationID,
                phase: .reconcile,
                primaryFailure: "The interrupted Trash operation could not be rolled back.",
                compensationFailures: failures,
                recoveryDirectory: trashOperationDirectory(
                    operationID: manifest.operationID,
                    location: location
                )
            )
        }
    }

    func recoveryError(
        operationID: UUID,
        message: String,
        location: ManagedLibraryLocation
    ) -> LibraryTrashTransactionError {
        LibraryTrashTransactionError(
            operationID: operationID,
            phase: .reconcile,
            primaryFailure: message,
            compensationFailures: [],
            recoveryDirectory: trashOperationDirectory(
                operationID: operationID,
                location: location
            )
        )
    }
}
