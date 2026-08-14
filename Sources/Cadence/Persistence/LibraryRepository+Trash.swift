import Foundation
import SwiftData

enum LibraryTrashError: Error, LocalizedError, Sendable {
    case destinationConflict
    case invalidManifest
    case missingManagedFile(String)
    case missingTarget
    case unavailableLibrary

    var errorDescription: String? {
        switch self {
        case .destinationConflict:
            "A managed file already exists at the restore destination."
        case .invalidManifest:
            "The Trash operation cannot be restored safely."
        case let .missingManagedFile(path):
            "A managed file is missing: \(path)"
        case .missingTarget:
            "The selected library item no longer exists."
        case .unavailableLibrary:
            "The managed library is unavailable."
        }
    }
}

struct LibraryTrashPlan {
    let tracks: [TrackRecord]
    let retainedTracks: [TrackRecord]
    let credits: [TrackArtistCreditRecord]
    let trackIDs: Set<UUID>
    let albums: [UUID: AlbumRecord]
    let artists: [UUID: ArtistRecord]
    let deletedAlbumIDs: Set<UUID>
    let deletedArtistIDs: Set<UUID>
    let targetArtistID: UUID?
    let artworks: [ArtworkRecord]
    let relativePaths: [String]
}

struct TrashCompensationContext {
    let operationID: UUID
    let phase: LibraryTrashTransactionPhase
    let manifestWasWritten: Bool
    let movedPaths: [(original: URL, trashed: URL)]
    let location: ManagedLibraryLocation
}

extension LibraryRepository {
    func trashTracks(
        targetIDs: [UUID],
        location: ManagedLibraryLocation
    ) throws -> [UUID] {
        var seen: Set<UUID> = []
        var operationIDs: [UUID] = []
        for targetID in targetIDs where seen.insert(targetID).inserted {
            try operationIDs.append(
                trash(
                    targetKind: .track,
                    targetID: targetID,
                    location: location
                )
            )
        }
        return operationIDs
    }

    func trash(
        targetKind: TrashTargetKind,
        targetID: UUID,
        location: ManagedLibraryLocation,
        operationID: UUID = UUID(),
        fileClient: TrashFileClient = .live
    ) throws -> UUID {
        let plan = try makeTrashPlan(
            kind: targetKind,
            id: targetID
        )
        let manifest = try makeTrashManifest(
            plan: plan,
            operationID: operationID,
            targetKind: targetKind
        )
        let manifestStore = ManagedTrashManifestStore(location: location)
        var movedPaths: [(original: URL, trashed: URL)] = []
        var phase = LibraryTrashTransactionPhase.writeManifest
        var manifestWasWritten = false
        do {
            // Recovery evidence must be durable before the first file mutation.
            try manifestStore.write(manifest)
            manifestWasWritten = true
            phase = .moveFiles
            try moveToTrash(
                relativePaths: plan.relativePaths,
                operationID: operationID,
                location: location,
                fileClient: fileClient,
                moved: &movedPaths
            )
            phase = .commitCatalog
            try commitTrash(
                plan,
                operationID: operationID,
                targetKind: targetKind
            )
            return operationID
        } catch {
            modelContext.rollback()
            throw compensateFailedTrash(
                primary: error,
                context: TrashCompensationContext(
                    operationID: operationID,
                    phase: phase,
                    manifestWasWritten: manifestWasWritten,
                    movedPaths: movedPaths,
                    location: location
                ),
                fileClient: fileClient
            )
        }
    }

    func trashOperations() throws -> [LibraryTrashProjection] {
        let records = try modelContext.fetch(
            FetchDescriptor<TrashOperationRecord>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
        let decoder = JSONDecoder()
        return try records.map { record in
            do {
                let ids = try decoder.decode(
                    [UUID].self,
                    from: record.targetIDsData
                )
                let paths = try decoder.decode(
                    [String].self,
                    from: record.originalRelativePathsData
                )
                return LibraryTrashProjection(
                    id: record.id,
                    targetKind: record.targetKind,
                    targetIDs: ids,
                    relativePaths: paths,
                    createdAt: record.createdAt
                )
            } catch {
                throw LibraryTrashError.invalidManifest
            }
        }
    }

    func emptyTrash(
        operationIDs: Set<UUID>? = nil,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient = .live
    ) throws {
        let records = try modelContext.fetch(
            FetchDescriptor<TrashOperationRecord>()
        ).filter {
            operationIDs?.contains($0.id) ?? true
        }
        // Commit metadata first. If that save fails, no permanent file deletion
        // has happened and SwiftData can roll back the entire request.
        let operationIDs = records.map(\.id)
        for record in records {
            modelContext.delete(record)
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        var cleanupFailures: [(operationID: UUID, message: String)] = []
        for operationID in operationIDs {
            do {
                try removeTrashOperationDirectory(
                    operationID: operationID,
                    location: location,
                    fileClient: fileClient
                )
            } catch {
                cleanupFailures.append(
                    (operationID, error.localizedDescription)
                )
            }
        }
        if let firstFailure = cleanupFailures.first {
            throw LibraryTrashTransactionError(
                operationID: firstFailure.operationID,
                phase: .cleanup,
                primaryFailure: firstFailure.message,
                compensationFailures: cleanupFailures.dropFirst().map {
                    "\($0.operationID.uuidString): \($0.message)"
                },
                recoveryDirectory: trashOperationDirectory(
                    operationID: firstFailure.operationID,
                    location: location
                )
            )
        }
    }
}
