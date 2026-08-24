import AVFoundation
@testable import Cadence
import Foundation
import SwiftData
import Testing

@MainActor
struct MetadataRepairIsolationTests {
    @Test("One unreadable candidate preserves healthy repairs and library readiness")
    func unreadableCandidateDoesNotBlockHealthyRepair() async throws {
        let fixture = try MetadataRepairIsolationFixture()
        defer { fixture.remove() }
        let session = LibrarySession.startup(location: fixture.location)
        #expect(session.availability == .empty)
        try fixture.installHealthyMedia()
        try await session.switchLocation(
            to: fixture.location,
            repository: fixture.repository
        )
        #expect(session.availability == .ready)
        #expect(session.store.availability == .ready)
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .unavailable("Metadata repair test"),
            librarySession: session
        )

        let reportedResult = await model.repairImportedMetadataIfNeeded()
        let result = try #require(reportedResult)

        #expect(result.repairedCount == 1)
        #expect(result.failures.map(\.trackID) == [fixture.missingTrackID])
        #expect(result.failedTrackIDs == Set([fixture.missingTrackID]))
        #expect(session.availability == .ready)
        #expect(session.store.availability == .ready)
        let records = try fixture.trackRecords()
        #expect(records[fixture.healthyTrackID]?.title == "Healthy Repair")
        #expect(records[fixture.healthyTrackID]?.sourceMetadata != nil)
        #expect(records[fixture.missingTrackID]?.sourceMetadata == nil)
        #expect(
            try await fixture.repository.metadataRepairCandidates()
                .items.map(\.id) == [fixture.missingTrackID]
        )

        let retryResult = try await ManagedMetadataRepairService(
            location: fixture.location,
            repository: fixture.repository
        ).repairAll()

        #expect(retryResult.repairedCount == 0)
        #expect(
            retryResult.failures.map(\.trackID) == [fixture.missingTrackID]
        )
        #expect(retryResult.failedTrackIDs == Set([fixture.missingTrackID]))
        #expect(session.availability == .ready)
        #expect(session.store.availability == .ready)
        #expect(
            try await fixture.repository.metadataRepairCandidates()
                .items.map(\.id) == [fixture.missingTrackID]
        )
    }
}

@MainActor
private struct MetadataRepairIsolationFixture {
    let root: URL
    let location: ManagedLibraryLocation
    let container: ModelContainer
    let repository: LibraryRepository
    let healthyTrackID: UUID
    let missingTrackID: UUID

    private static let healthyRelativePath = "Media/Healthy Repair.wav"

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Metadata-Repair-Isolation-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        let location = ManagedLibraryLocation(musicDirectory: root)
        let container = try LibraryContainerFactory.inMemory()
        let (healthyTrack, missingTrack) = try Self.insertTracks(
            into: ModelContext(container)
        )

        self.root = root
        self.location = location
        self.container = container
        repository = LibraryRepository(modelContainer: container)
        healthyTrackID = healthyTrack.id
        missingTrackID = missingTrack.id
    }

    func installHealthyMedia() throws {
        try ManagedLibraryPackage(location: location)
            .bootstrapForConfirmedImport()
        try writeSilentWAV(
            to: location.resolve(relativePath: Self.healthyRelativePath)
        )
    }

    func trackRecords() throws -> [UUID: TrackRecord] {
        let records = try ModelContext(container).fetch(
            FetchDescriptor<TrackRecord>()
        )
        return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func insertTracks(
        into context: ModelContext
    ) throws -> (healthy: TrackRecord, missing: TrackRecord) {
        let unknownArtist = ArtistRecord(
            name: "Unknown Artist",
            trackCount: 2,
            albumCount: 1
        )
        let unknownAlbum = AlbumRecord(
            title: "Unknown Album",
            artist: unknownArtist,
            trackCount: 2,
            totalDuration: 240
        )
        let healthyTrack = Self.makeTrack(
            TrackSeed(
                originalFilename: "Healthy Repair.wav",
                title: "Healthy Legacy",
                contentHash: String(repeating: "a", count: 64),
                relativeMediaPath: healthyRelativePath
            ),
            artist: unknownArtist,
            album: unknownAlbum
        )
        let missingTrack = Self.makeTrack(
            TrackSeed(
                originalFilename: "Missing Repair.wav",
                title: "Missing Legacy",
                contentHash: String(repeating: "b", count: 64),
                relativeMediaPath: "Media/Missing Repair.wav"
            ),
            artist: unknownArtist,
            album: unknownAlbum
        )
        context.insert(unknownArtist)
        context.insert(unknownAlbum)
        context.insert(healthyTrack)
        context.insert(missingTrack)
        try context.save()
        return (healthyTrack, missingTrack)
    }

    private struct TrackSeed {
        let originalFilename: String
        let title: String
        let contentHash: String
        let relativeMediaPath: String
    }

    private static func makeTrack(
        _ seed: TrackSeed,
        artist: ArtistRecord,
        album: AlbumRecord
    ) -> TrackRecord {
        TrackRecord(
            originalFilename: seed.originalFilename,
            title: seed.title,
            duration: 120,
            codec: "wav",
            container: "WAV",
            sampleRate: 44100,
            channelCount: 2,
            contentHash: seed.contentHash,
            relativeMediaPath: seed.relativeMediaPath,
            importSessionID: UUID(),
            artist: artist,
            album: album
        )
    }

    private func writeSilentWAV(to url: URL) throws {
        let format = try #require(
            AVAudioFormat(
                standardFormatWithSampleRate: 44100,
                channels: 2
            )
        )
        let frameCount: AVAudioFrameCount = 4410
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            )
        )
        buffer.frameLength = frameCount
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings
        )
        try file.write(from: buffer)
    }
}
