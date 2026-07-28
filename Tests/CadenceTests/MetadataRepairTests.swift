@testable import Cadence
import Foundation
import SwiftData
import Testing

@MainActor
struct MetadataRepairTests {
    @Test("Legacy fallback metadata is repaired without leaving empty groups")
    func repairsFallbackRecords() async throws {
        let (container, trackID) = try makeLegacyStore()
        let repository = LibraryRepository(modelContainer: container)
        let candidates = try await repository.metadataRepairCandidates()
        #expect(candidates.items.map(\.id) == [trackID])

        let metadata = ManagedImportManifest.Metadata(
            title: "BLUE",
            artist: "Billie Eilish",
            album: "HIT ME HARD AND SOFT",
            year: 2024,
            trackNumber: 10,
            discNumber: 1,
            duration: 343,
            codec: "flac",
            container: "FLAC",
            sampleRate: 44100,
            channelCount: 2,
            bitrate: 900_000,
            bitDepth: 24,
            spatialFormat: .stereo
        )
        let sourceMetadata = try JSONEncoder().encode(metadata)

        let repairedCount = try await repository.applyMetadataRepairs([
            ManagedMetadataRepair(
                trackID: trackID,
                metadata: metadata,
                sourceMetadata: sourceMetadata
            ),
        ])

        let tracks = try await repository.tracksPage()
        let artists = try await repository.artistsPage()
        let albums = try await repository.albumsPage()
        let remainingCandidates = try await repository
            .metadataRepairCandidates()

        #expect(repairedCount == 1)
        #expect(tracks.items.map(\.title) == ["BLUE"])
        #expect(tracks.items.map(\.artist) == ["Billie Eilish"])
        #expect(tracks.items.map(\.album) == ["HIT ME HARD AND SOFT"])
        #expect(artists.items.map(\.name) == ["Billie Eilish"])
        #expect(albums.items.map(\.title) == ["HIT ME HARD AND SOFT"])
        #expect(albums.items.first?.year == 2024)
        #expect(remainingCandidates.items.isEmpty)
    }

    private func makeLegacyStore() throws -> (ModelContainer, UUID) {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let unknownArtist = ArtistRecord(
            name: "Unknown Artist",
            trackCount: 1,
            albumCount: 1
        )
        let unknownAlbum = AlbumRecord(
            title: "Unknown Album",
            artist: unknownArtist,
            trackCount: 1,
            totalDuration: 120
        )
        let track = TrackRecord(
            originalFilename: "10-Billie-Eilish-BLUE.flac",
            title: "10-Billie-Eilish-BLUE",
            duration: 120,
            codec: "flac",
            container: "FLAC",
            sampleRate: 44100,
            channelCount: 2,
            contentHash: String(repeating: "a", count: 64),
            relativeMediaPath: "Media/legacy.flac",
            importSessionID: UUID(),
            artist: unknownArtist,
            album: unknownAlbum
        )
        context.insert(unknownArtist)
        context.insert(unknownAlbum)
        context.insert(track)
        try context.save()
        return (container, track.id)
    }
}
