import Foundation

typealias LibraryTrashTargetOperation = @Sendable (
    _ repository: LibraryRepository,
    _ targetKind: TrashTargetKind,
    _ targetID: UUID,
    _ location: ManagedLibraryLocation
) async throws -> UUID

extension LibraryStore {
    func moveToTrash(
        trackIDs: [UUID],
        location: ManagedLibraryLocation?
    ) async throws {
        guard let location else {
            throw LibraryTrashError.unavailableLibrary
        }
        let context = captureLibraryContext()
        let repository = try requireRepository()
        do {
            _ = try await repository.trashTracks(
                targetIDs: trackIDs,
                location: location
            )
        } catch let error as LibraryTrashBatchError {
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            await refreshAfterSemanticTrackMutation()
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            throw error
        } catch {
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            throw error
        }
        guard isCurrentLibraryContext(context) else {
            return
        }
        await refreshAfterSemanticTrackMutation()
    }

    func moveToTrash(
        targetKind: TrashTargetKind,
        targetID: UUID,
        location: ManagedLibraryLocation?,
        operation: LibraryTrashTargetOperation? = nil
    ) async throws {
        guard let location else {
            throw LibraryTrashError.unavailableLibrary
        }
        let context = captureLibraryContext()
        let repository = try requireRepository()
        do {
            if let operation {
                _ = try await operation(
                    repository,
                    targetKind,
                    targetID,
                    location
                )
            } else {
                _ = try await repository.trash(
                    targetKind: targetKind,
                    targetID: targetID,
                    location: location
                )
            }
        } catch {
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            throw error
        }
        guard isCurrentLibraryContext(context) else {
            return
        }
        await refreshAfterSemanticTrackMutation()
    }

    func emptyTrash(
        operationIDs: Set<UUID>? = nil,
        location: ManagedLibraryLocation?
    ) async throws {
        guard let location else {
            throw LibraryTrashError.unavailableLibrary
        }
        let context = captureLibraryContext()
        let repository = try requireRepository()
        do {
            try await repository.emptyTrash(
                operationIDs: operationIDs,
                location: location
            )
        } catch let error as LibraryTrashTransactionError
            where error.phase == .cleanup {
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            await loadInitialLibrary()
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            throw error
        } catch {
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            throw error
        }
        guard isCurrentLibraryContext(context) else {
            return
        }
        await loadInitialLibrary()
    }

    func restoreTrash(
        operationID: UUID,
        location: ManagedLibraryLocation?
    ) async throws {
        guard let location else {
            throw LibraryTrashError.unavailableLibrary
        }
        let context = captureLibraryContext()
        let repository = try requireRepository()
        do {
            try await repository.restoreTrash(
                operationID: operationID,
                location: location
            )
        } catch let error as LibraryTrashTransactionError
            where error.phase == .cleanup {
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            await refreshAfterSemanticTrackMutation()
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            throw error
        } catch {
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            throw error
        }
        guard isCurrentLibraryContext(context) else {
            return
        }
        await refreshAfterSemanticTrackMutation()
    }
}
