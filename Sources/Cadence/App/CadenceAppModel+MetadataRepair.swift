import Foundation

extension CadenceAppModel {
    func repairImportedMetadataIfNeeded() async {
        guard
            librarySession.availability == .ready,
            let location = librarySession.location,
            let repository = librarySession.store.repository
        else {
            return
        }

        do {
            let repairedCount = try await ManagedMetadataRepairService(
                location: location,
                repository: repository
            ).repairAll()
            if repairedCount > 0 {
                await librarySession.store.loadInitialLibrary()
            }
        } catch {
            librarySession.fail(
                message: "Couldn’t repair imported metadata: "
                    + error.localizedDescription
            )
        }
    }
}
