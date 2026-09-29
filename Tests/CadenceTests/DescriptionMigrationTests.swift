@testable import Cadence
import Foundation
import SwiftData
import Testing

struct DescriptionMigrationTests {
    @Test("Version six artists migrate with an empty optional description")
    func versionSixArtistDescriptionMigration() throws {
        try withDescriptionMigrationDirectory { directory in
            let storeURL = directory.appending(path: "VersionSix.store")
            let artistID = UUID()
            try createVersionSixStore(at: storeURL, artistID: artistID)

            let container = try openDescriptionMigratedStore(at: storeURL)
            let context = ModelContext(container)
            let artists = try context.fetch(FetchDescriptor<ArtistRecord>())
            let descriptions = try context.fetch(
                FetchDescriptor<ArtistDescriptionRecord>()
            )

            #expect(artists.map(\.id) == [artistID])
            #expect(descriptions.isEmpty)
        }
    }

    @Test("Version five playlists and Smart Collections gain optional descriptions")
    func versionFiveDescriptionMigration() throws {
        try withDescriptionMigrationDirectory { directory in
            let storeURL = directory.appending(path: "VersionFive.store")
            let playlistID = UUID()
            let collectionID = UUID()
            try createVersionFiveStore(
                at: storeURL,
                playlistID: playlistID,
                collectionID: collectionID
            )

            let container = try openDescriptionMigratedStore(at: storeURL)
            let context = ModelContext(container)
            let playlist = try #require(
                context.fetch(FetchDescriptor<PlaylistRecord>()).first
            )
            let collection = try #require(
                context.fetch(FetchDescriptor<SmartCollectionRecord>()).first
            )

            #expect(playlist.id == playlistID)
            #expect(playlist.userDescription == nil)
            #expect(collection.id == collectionID)
            #expect(collection.userDescription == nil)
        }
    }
}

private func createVersionFiveStore(
    at storeURL: URL,
    playlistID: UUID,
    collectionID: UUID
) throws {
    let schema = Schema(versionedSchema: CadenceSchemaV5.self)
    let configuration = ModelConfiguration(
        "CadenceVersionFiveFixture",
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    context.insert(
        CadenceLegacySchemaModels.PlaylistRecord(
            id: playlistID,
            name: "Legacy Playlist"
        )
    )
    context.insert(
        CadenceLegacySchemaModels.SmartCollectionRecord(
            id: collectionID,
            name: "Legacy Collection",
            ruleData: Data("legacy".utf8),
            sortDescriptorRawValue: "canonical:ascending",
            playbackPreferenceRawValue: "ordered"
        )
    )
    try context.save()
}

private func createVersionSixStore(at storeURL: URL, artistID: UUID) throws {
    let schema = Schema(versionedSchema: CadenceSchemaV6.self)
    let configuration = ModelConfiguration(
        "CadenceVersionSixFixture",
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    context.insert(ArtistRecord(id: artistID, name: "Legacy Artist"))
    try context.save()
}

private func openDescriptionMigratedStore(at storeURL: URL) throws -> ModelContainer {
    let schema = Schema(versionedSchema: CadenceSchemaV7.self)
    let configuration = ModelConfiguration(
        "CadenceDescriptionMigrationFixture",
        schema: schema,
        url: storeURL,
        cloudKitDatabase: .none
    )
    return try ModelContainer(
        for: schema,
        migrationPlan: CadenceMigrationPlan.self,
        configurations: [configuration]
    )
}

private func withDescriptionMigrationDirectory(
    _ operation: (URL) throws -> Void
) throws {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "CadenceDescriptionMigrationTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try operation(directory)
}
