import Foundation

extension CadenceAppModel {
    func bootstrapCloudLibraryIfNeeded(
        identityStore: CloudLibraryIdentityStore? = nil
    ) async {
        guard !CadenceLaunchEnvironment.shouldUsePreviewLibrary(),
              runtimeMode == .production,
              librarySession.availability == .empty,
              let location = librarySession.location else {
            return
        }
        do {
            let identityStore = identityStore ?? CloudLibraryIdentityStore()
            guard let identity = try await identityStore.remoteIdentity() else {
                return
            }
            let package = ManagedLibraryPackage(location: location)
            try package.bootstrapForConfirmedImport()
            try package.writeIdentity(identity)
            let container = try LibraryContainerFactory.persistentReplica(
                package: package
            )
            let repository = LibraryRepository(modelContainer: container)
            await librarySession.activate(repository: repository)
            configureImportPipeline(
                location: location,
                repository: repository
            )
        } catch {
            librarySession.fail(
                kind: .openFailed,
                message: error.localizedDescription
            )
        }
    }
}
