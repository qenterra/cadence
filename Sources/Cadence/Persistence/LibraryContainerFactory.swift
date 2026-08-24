import Foundation
import SwiftData

struct LibraryContainerMigrationRollbackError: Error, LocalizedError, Sendable {
    let openFailure: String
    let rollbackFailure: String

    var errorDescription: String? {
        "The local catalog could not be opened (\(openFailure)); "
            + "rollback also failed (\(rollbackFailure))."
    }
}

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
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil,
        migration: LocalLibraryCatalogMigration = LocalLibraryCatalogMigration(),
        openStore: ((URL) throws -> ModelContainer)? = nil
    ) throws -> ModelContainer {
        let identity = try readLocalCatalogIdentity(
            package: package,
            fileManager: fileManager
        )
        let localCatalog = if let applicationSupportDirectory {
            LocalLibraryCatalogLocation(
                applicationSupportDirectory: applicationSupportDirectory,
                identity: identity
            )
        } else {
            try LocalLibraryCatalogLocation.currentUser(
                identity: identity,
                fileManager: fileManager
            )
        }
        let transactionLock = try LocalCatalogTransactionLock.acquire(
            at: localCatalog.transactionLockURL,
            trustedRoot: localCatalog.applicationSupportDirectoryURL,
            fileManager: fileManager
        )
        defer { withExtendedLifetime(transactionLock) {} }
        let prepared = try migration.prepareIfNeeded(
            package: package,
            applicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager
        )
        do {
            try fileManager.createDirectory(
                at: localCatalog.metadataDirectoryURL,
                withIntermediateDirectories: true
            )
            let container = if let openStore {
                try openStore(localCatalog.storeURL)
            } else {
                try persistent(storeURL: localCatalog.storeURL)
            }
            try migration.recordSuccessfulCatalogOpen(
                package: package,
                libraryID: identity.id,
                fileManager: fileManager
            )
            if let prepared {
                try migration.commit(prepared, fileManager: fileManager)
            }
            return container
        } catch {
            if let prepared {
                do {
                    try migration.rollback(prepared, fileManager: fileManager)
                } catch let rollbackError {
                    throw LibraryContainerMigrationRollbackError(
                        openFailure: error.localizedDescription,
                        rollbackFailure: rollbackError.localizedDescription
                    )
                }
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
