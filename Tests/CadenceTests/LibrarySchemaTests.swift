@testable import Cadence
import Foundation
import SwiftData
import Testing

struct LibrarySchemaTests {
    @Test("Current schema declares every durable functional-core model")
    func schemaModels() throws {
        let container = try LibraryContainerFactory.inMemory()
        let entityNames = Set(container.schema.entities.map(\.name))

        #expect(CadenceSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
        #expect(
            entityNames == [
                "AlbumRecord",
                "ArtistRecord",
                "ArtworkRecord",
                "ImportSessionRecord",
                "LyricRecord",
                "PlaylistEntryRecord",
                "PlaylistRecord",
                "SmartCollectionRecord",
                "TagAssignmentRecord",
                "TagExclusionRecord",
                "TagRecord",
                "TrackRecord",
                "TrackArtistCreditRecord",
                "TrashOperationRecord",
            ]
        )
    }

    @Test("Track, artist, album, lyrics, and import session round trip")
    func coreRoundTrip() throws {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let importID = UUID()
        let artist = ArtistRecord(name: "North Assembly")
        let album = AlbumRecord(
            title: "Signals After Dark",
            artist: artist,
            year: 2026
        )
        let session = ImportSessionRecord(
            id: importID,
            sourceDisplayName: "Lossless",
            state: .complete
        )
        let track = TrackRecord(
            originalFilename: "Midnight Static.flac",
            title: "Midnight Static",
            duration: 277,
            codec: "FLAC",
            container: "FLAC",
            sampleRate: 96000,
            channelCount: 2,
            bitDepth: 24,
            contentHash: String(repeating: "a", count: 64),
            relativeMediaPath: "Media/track.flac",
            importSessionID: importID,
            artist: artist,
            album: album
        )
        let lyrics = LyricRecord(
            relativePath: "Lyrics/track.lrc",
            contentHash: String(repeating: "b", count: 64),
            timingStatus: .synchronized,
            track: track
        )
        track.lyrics = lyrics

        context.insert(session)
        context.insert(artist)
        context.insert(album)
        context.insert(track)
        context.insert(lyrics)
        try context.save()

        let savedTracks = try context.fetch(FetchDescriptor<TrackRecord>())
        let savedTrack = try #require(savedTracks.first)

        #expect(savedTracks.count == 1)
        #expect(savedTrack.artist?.name == "North Assembly")
        #expect(savedTrack.album?.title == "Signals After Dark")
        #expect(savedTrack.lyrics?.timingStatus == .synchronized)
        #expect(savedTrack.importSessionID == session.id)
        #expect(savedTrack.bitDepth == 24)
    }

    @Test("Persistent configuration uses the managed metadata store")
    func persistentStoreLocation() throws {
        try withTemporaryDirectory { musicDirectory in
            let package = ManagedLibraryPackage(
                location: ManagedLibraryLocation(
                    musicDirectory: musicDirectory
                )
            )
            try package.bootstrapForConfirmedImport()

            let container = try LibraryContainerFactory.persistent(
                package: package
            )
            let configuration = try #require(
                container.configurations.first
            )

            #expect(configuration.url == package.metadataStoreURL)
            #expect(
                FileManager.default.fileExists(
                    atPath: package.metadataStoreURL.path
                )
            )
        }
    }

    @Test("Version one stores migrate to the current schema without data loss")
    func versionOneMigration() throws {
        try withTemporaryDirectory { directory in
            let storeURL = directory.appending(
                path: "Migration.store",
                directoryHint: .notDirectory
            )
            let trackID = UUID()
            let importID = UUID()

            try createVersionOneStore(
                at: storeURL,
                trackID: trackID,
                importID: importID
            )
            let migratedContainer = try openMigratedStore(at: storeURL)
            try LibraryContainerFactory.backfillArtistCredits(
                in: migratedContainer
            )
            let migratedContext = ModelContext(migratedContainer)

            #expect(
                try migratedContext.fetch(FetchDescriptor<TrackRecord>())
                    .map(\.title) == ["Signal"]
            )
            #expect(
                try migratedContext.fetch(
                    FetchDescriptor<TrashOperationRecord>()
                )
                .isEmpty
            )
            let credits = try migratedContext.fetch(
                FetchDescriptor<TrackArtistCreditRecord>()
            )
            #expect(credits.count == 1)
            #expect(credits.first?.trackID == trackID)
            let legacyArtist = try migratedContext.fetch(
                FetchDescriptor<ArtistRecord>()
            ).first
            #expect(credits.first?.artistID == legacyArtist?.id)
            #expect(legacyArtist?.name == "Legacy Artist")
        }
    }

    private func createVersionOneStore(
        at storeURL: URL,
        trackID: UUID,
        importID: UUID
    ) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV1.self)
        let configuration = ModelConfiguration(
            "CadenceMigrationFixture",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let artist = ArtistRecord(name: "Legacy Artist", trackCount: 1)
        context.insert(artist)
        context.insert(
            ImportSessionRecord(
                id: importID,
                sourceDisplayName: "Migration Fixture",
                state: .complete,
                importedCount: 1
            )
        )
        context.insert(
            TrackRecord(
                id: trackID,
                originalFilename: "Signal.flac",
                title: "Signal",
                duration: 180,
                codec: "FLAC",
                container: "FLAC",
                sampleRate: 48000,
                channelCount: 2,
                contentHash: String(repeating: "a", count: 64),
                relativeMediaPath: "Media/\(trackID.uuidString).flac",
                importSessionID: importID,
                artist: artist
            )
        )
        try context.save()
    }

    private func openMigratedStore(
        at storeURL: URL
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV4.self)
        let configuration = ModelConfiguration(
            "CadenceMigrationFixture",
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

    @Test("In-memory stores never create the real managed package")
    func inMemoryHasNoPackageSideEffect() throws {
        try withTemporaryDirectory { musicDirectory in
            let location = ManagedLibraryLocation(
                musicDirectory: musicDirectory
            )

            _ = try LibraryContainerFactory.inMemory()

            #expect(
                !FileManager.default.fileExists(
                    atPath: location.packageURL.path
                )
            )
        }
    }

    private func withTemporaryDirectory(
        _ operation: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "CadenceSchemaTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try operation(directory)
    }
}
