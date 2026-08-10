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
        let schema = Schema(versionedSchema: CadenceSchemaV5.self)
        let configuration = ModelConfiguration(
            "CadenceLibrary",
            schema: schema,
            url: package.metadataStoreURL,
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
