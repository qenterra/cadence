import Foundation

actor ManagedLibraryImportDestination {
    let package: ManagedLibraryPackage
    private var repository: LibraryRepository?

    init(
        package: ManagedLibraryPackage,
        repository: LibraryRepository?
    ) {
        self.package = package
        self.repository = repository
    }

    func prepareRepository() throws -> LibraryRepository {
        if let repository {
            return repository
        }
        try package.bootstrapForConfirmedImport()
        try package.createIdentityIfNeeded()
        let container = try LibraryContainerFactory.persistentReplica(
            package: package
        )
        let repository = LibraryRepository(modelContainer: container)
        self.repository = repository
        return repository
    }

    func currentRepository() -> LibraryRepository? {
        repository
    }

    func duplicateEvidence(
        probes: [ImportDuplicateProbe]
    ) async throws -> ImportDuplicateEvidence {
        guard let repository else {
            return .empty
        }
        return try await repository.importDuplicateEvidence(probes: probes)
    }
}
