import Foundation

extension LibraryStore {
    func moveToTrash(
        targetKind: TrashTargetKind,
        targetID: UUID,
        location: ManagedLibraryLocation?
    ) async throws {
        guard let repository, let location else {
            throw LibraryTrashError.unavailableLibrary
        }
        _ = try await repository.trash(
            targetKind: targetKind,
            targetID: targetID,
            location: location
        )
        await loadInitialLibrary()
    }

    func emptyTrash(
        operationIDs: Set<UUID>? = nil,
        location: ManagedLibraryLocation?
    ) async throws {
        guard let repository, let location else {
            throw LibraryTrashError.unavailableLibrary
        }
        try await repository.emptyTrash(
            operationIDs: operationIDs,
            location: location
        )
        await loadInitialLibrary()
    }

    func restoreTrash(
        operationID: UUID,
        location: ManagedLibraryLocation?
    ) async throws {
        guard let repository, let location else {
            throw LibraryTrashError.unavailableLibrary
        }
        try await repository.restoreTrash(
            operationID: operationID,
            location: location
        )
        await loadInitialLibrary()
    }
}
