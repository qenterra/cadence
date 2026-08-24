import Foundation

typealias ManagedMetadataRepairOperation = @Sendable (
    _ location: ManagedLibraryLocation,
    _ repository: LibraryRepository
) async throws -> ManagedMetadataRepairResult

extension CadenceAppModel {
    @discardableResult
    func repairImportedMetadataIfNeeded(
        operation: ManagedMetadataRepairOperation? = nil
    ) async -> ManagedMetadataRepairResult? {
        guard
            librarySession.availability == .ready,
            let location = librarySession.location
        else {
            return nil
        }

        let transitionGeneration = librarySession.transitionGeneration
        let context = librarySession.store.captureLibraryContext()
        do {
            let repository = try librarySession.store.requireRepository()
            let result = if let operation {
                try await operation(location, repository)
            } else {
                try await ManagedMetadataRepairService(
                    location: location,
                    repository: repository
                ).repairAll()
            }
            guard ownsMetadataRepair(
                transitionGeneration: transitionGeneration,
                context: context
            ) else {
                return nil
            }
            await librarySession.store.refreshAfterMetadataRepair(
                repairedCount: result.repairedCount,
                context: context
            )
            guard ownsMetadataRepair(
                transitionGeneration: transitionGeneration,
                context: context
            ) else {
                return nil
            }
            return result
        } catch is CancellationError {
            return nil
        } catch {
            guard ownsMetadataRepair(
                transitionGeneration: transitionGeneration,
                context: context
            ) else {
                return nil
            }
            librarySession.fail(
                message: "Couldn’t repair imported metadata: "
                    + error.localizedDescription
            )
            return nil
        }
    }

    private func ownsMetadataRepair(
        transitionGeneration: UInt64,
        context: LibraryStoreContext
    ) -> Bool {
        librarySession.transitionGeneration == transitionGeneration
            && librarySession.store.isCurrentLibraryContext(context)
    }
}
