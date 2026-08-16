@testable import Cadence
import Foundation
import SwiftData
import Testing

struct CloudLibrarySyncTests {
    @Test("Newer user intent wins even when an older device uploads later")
    func conflictResolution() {
        let libraryID = UUID()
        let entity = CloudLibraryEntity(
            kind: .playlist,
            id: UUID(),
            payload: Data("older".utf8)
        )
        let old = CloudLibraryRecord.live(
            libraryID: libraryID,
            entity: entity,
            modifiedAt: Date(timeIntervalSince1970: 10),
            deviceID: UUID()
        )
        let newer = CloudLibraryRecord.live(
            libraryID: libraryID,
            entity: CloudLibraryEntity(
                kind: entity.kind,
                id: entity.id,
                payload: Data("newer".utf8)
            ),
            modifiedAt: Date(timeIntervalSince1970: 20),
            deviceID: UUID()
        )

        #expect(
            CloudLibraryConflictResolver.preferred(
                local: old,
                remote: newer
            ) == newer
        )
    }

    @Test("A tombstone wins an equal-time conflict")
    func tombstoneWinsTie() {
        let entity = CloudLibraryEntity(
            kind: .track,
            id: UUID(),
            payload: Data("track".utf8)
        )
        let live = CloudLibraryRecord.live(
            libraryID: UUID(),
            entity: entity,
            modifiedAt: .distantPast,
            deviceID: UUID()
        )
        let tombstone = CloudLibraryRecord.tombstone(
            replacing: live,
            modifiedAt: live.userModificationDate,
            deviceID: UUID()
        )

        #expect(
            CloudLibraryConflictResolver.preferred(
                local: live,
                remote: tombstone
            ) == tombstone
        )
    }

    @Test("Catalog entities round-trip through cloud payloads")
    func catalogRoundTrip() async throws {
        let sourceContainer = try LibraryContainerFactory.inMemory()
        let sourceContext = ModelContext(sourceContainer)
        let artist = ArtistRecord(name: "Veilr")
        let album = AlbumRecord(title: "Signals", artist: artist, year: 2026)
        let track = TrackRecord(
            originalFilename: "Signal.flac",
            title: "The Signal",
            duration: 240,
            codec: "FLAC",
            container: "FLAC",
            sampleRate: 96000,
            channelCount: 2,
            bitDepth: 24,
            contentHash: "abc123",
            relativeMediaPath: "Media/Signal.flac",
            importSessionID: UUID(),
            artist: artist,
            album: album
        )
        sourceContext.insert(artist)
        sourceContext.insert(album)
        sourceContext.insert(track)
        try sourceContext.save()
        let sourceRepository = LibraryRepository(
            modelContainer: sourceContainer
        )
        let entities = try await sourceRepository.exportCloudEntities()
        let libraryID = UUID()
        let deviceID = UUID()
        let records = entities.map {
            CloudLibraryRecord.live(
                libraryID: libraryID,
                entity: $0,
                modifiedAt: .now,
                deviceID: deviceID
            )
        }

        let destinationContainer = try LibraryContainerFactory.inMemory()
        let destinationRepository = LibraryRepository(
            modelContainer: destinationContainer
        )
        try await destinationRepository.applyCloudRecords(records)
        let tracks = try await destinationRepository.tracksPage(limit: 10)

        #expect(tracks.items.map(\.title) == ["The Signal"])
        #expect(tracks.items.first?.artist == "Veilr")
        #expect(tracks.items.first?.album == "Signals")
    }
}
