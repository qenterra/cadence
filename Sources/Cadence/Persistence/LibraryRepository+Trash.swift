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

struct LibraryTrashBatchError: Error, LocalizedError, Sendable {
    let completedOperationIDs: [UUID]
    let requestedTargetCount: Int
    let failedTargetID: UUID
    let cause: any Error

    var completedTargetCount: Int {
        completedOperationIDs.count
    }

    var errorDescription: String? {
        "\(completedTargetCount) of \(requestedTargetCount) selected tracks "
            + "moved to Trash before another item failed: "
            + cause.localizedDescription
    }
}

private extension TrashTargetKind {
    var fallbackTitle: String {
        switch self {
        case .track: String(localized: "Removed Track")
        case .album: String(localized: "Removed Album")
        case .artist: String(localized: "Removed Artist")
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
            do {
                try operationIDs.append(
                    trash(
                        targetKind: .track,
                        targetID: targetID,
                        location: location
                    )
                )
            } catch {
                guard !operationIDs.isEmpty else {
                    throw error
                }
                throw LibraryTrashBatchError(
                    completedOperationIDs: operationIDs,
                    requestedTargetCount: Set(targetIDs).count,
                    failedTargetID: targetID,
                    cause: error
                )
            }
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

    func trashOperations(
        location: ManagedLibraryLocation? = nil
    ) throws -> [LibraryTrashProjection] {
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
                let labels = location.flatMap { location in
                    try? trashLabels(
                        manifest: ManagedTrashManifestStore(location: location)
                            .read(operationID: record.id),
                        targetIDs: ids
                    )
                }
                return LibraryTrashProjection(
                    id: record.id,
                    targetKind: record.targetKind,
                    targetIDs: ids,
                    relativePaths: paths,
                    createdAt: record.createdAt,
                    displayTitle: labels?.title ?? record.targetKind.fallbackTitle,
                    displaySubtitle: labels?.subtitle
                )
            } catch {
                throw LibraryTrashError.invalidManifest
            }
        }
    }

    private func trashLabels(
        manifest: ManagedTrashManifest,
        targetIDs: [UUID]
    ) -> (title: String, subtitle: String?) {
        let targetID = targetIDs.first ?? manifest.targetID
        switch manifest.targetKind {
        case .track:
            let track = manifest.tracks.first { $0.id == targetID }
                ?? manifest.tracks.first
            let artist = track?.artistID.flatMap { artistID in
                manifest.artists.first { $0.id == artistID }?.name
            } ?? manifest.artistCredits?
                .first(where: { $0.trackID == track?.id })?
                .displayArtistName
            return (track?.title ?? manifest.targetKind.fallbackTitle, artist)
        case .album:
            let album = manifest.albums.first { $0.id == targetID }
                ?? manifest.albums.first
            let artist = album?.artistID.flatMap { artistID in
                manifest.artists.first { $0.id == artistID }?.name
            }
            return (album?.title ?? manifest.targetKind.fallbackTitle, artist)
        case .artist:
            let artist = manifest.artists.first { $0.id == targetID }
                ?? manifest.artists.first
            return (artist?.name ?? manifest.targetKind.fallbackTitle, nil)
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

    @discardableResult
    func emptyExpiredTrash(
        olderThan cutoff: Date,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient = .live
    ) throws -> Int {
        let expiredIDs = try Set(
            modelContext.fetch(FetchDescriptor<TrashOperationRecord>())
                .filter { record in
                    record.completedAt.map { $0 < cutoff } == true
                }
                .map(\.id)
        )
        guard !expiredIDs.isEmpty else {
            return 0
        }
        try emptyTrash(
            operationIDs: expiredIDs,
            location: location,
            fileClient: fileClient
        )
        return expiredIDs.count
    }
}
