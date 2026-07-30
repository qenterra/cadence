import SwiftData

enum LibraryContainerFactory {
    static func inMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV3.self)
        let configuration = ModelConfiguration(
            "CadenceInMemory",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: CadenceMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func persistent(
        package: ManagedLibraryPackage
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV3.self)
        let configuration = ModelConfiguration(
            "CadenceLibrary",
            schema: schema,
            url: package.metadataStoreURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: CadenceMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
