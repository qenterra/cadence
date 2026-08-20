import Foundation
import SwiftData

enum LibraryContainerFactory {
    static func inMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV5.self)
        let configuration = ModelConfiguration(
            "CadenceInMemory",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CadenceMigrationPlan.self,
            configurations: [configuration]
        )
        try backfillArtistCredits(in: container)
        return container
    }

    static func persistent(
        package: ManagedLibraryPackage
    ) throws -> ModelContainer {
        try persistent(storeURL: package.metadataStoreURL)
    }

    static func persistentLocal(
        package: ManagedLibraryPackage,
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        let identity = try package.readIdentity()
        let localCatalog = try LocalLibraryCatalogLocation.currentUser(
            identity: identity,
            fileManager: fileManager
        )
        let migration = LocalLibraryCatalogMigration()
        let prepared = try migration.prepareIfNeeded(
            package: package,
            fileManager: fileManager
        )
        do {
            try fileManager.createDirectory(
                at: localCatalog.metadataDirectoryURL,
                withIntermediateDirectories: true
            )
            let container = try persistent(storeURL: localCatalog.storeURL)
            if let prepared {
                try migration.commit(prepared, fileManager: fileManager)
            }
            return container
        } catch {
            if let prepared {
                try? migration.rollback(prepared, fileManager: fileManager)
            }
            throw error
        }
    }

    private static func persistent(
        storeURL: URL
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV5.self)
        let configuration = ModelConfiguration(
            "CadenceLibrary",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CadenceMigrationPlan.self,
            configurations: [configuration]
        )
        try backfillArtistCredits(in: container)
        return container
    }

    static func backfillArtistCredits(
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let existingTrackIDs = try Set(
            context.fetch(FetchDescriptor<TrackArtistCreditRecord>())
                .map(\.trackID)
        )
        let tracks = try context.fetch(FetchDescriptor<TrackRecord>())
        var inserted = false
        for track in tracks where !existingTrackIDs.contains(track.id) {
            guard let artist = track.artist else {
                continue
            }
            context.insert(
                TrackArtistCreditRecord(
                    track: track,
                    artist: artist,
                    position: 0,
                    displayArtistName: artist.name
                )
            )
            inserted = true
        }
        if inserted {
            try context.save()
        }
    }
}
