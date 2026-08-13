@testable import Cadence
import Foundation
import SwiftData
import Testing

struct PlaylistRepositoryTests {
    @Test("Manual playlists preserve order and reject duplicate tracks")
    func manualPlaylistLifecycle() async throws {
        let container = try makeContainer(
            titles: ["Track 1", "Track 2", "Track 3"]
        )
        let context = ModelContext(container)
        let tracks = try context.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [SortDescriptor(\.normalizedTitle)]
            )
        )
        let repository = LibraryRepository(modelContainer: container)
        let playlist = try await repository.createPlaylist(
            name: "  Late Night  "
        )

        try await repository.addToPlaylist(
            playlistID: playlist.id,
            trackIDs: [tracks[2].id, tracks[0].id, tracks[2].id]
        )
        #expect(
            try await repository.playlistTracks(
                playlistID: playlist.id
            ).map(\.id) == [tracks[2].id, tracks[0].id]
        )

        try await repository.reorderPlaylist(
            playlistID: playlist.id,
            orderedTrackIDs: [tracks[0].id, tracks[2].id]
        )
        #expect(
            try await repository.playlistTracks(
                playlistID: playlist.id
            ).map(\.id) == [tracks[0].id, tracks[2].id]
        )

        try await repository.removeFromPlaylist(
            playlistID: playlist.id,
            trackIDs: [tracks[0].id]
        )
        try await repository.renamePlaylist(
            id: playlist.id,
            name: "Quiet Hours"
        )
        let updated = try #require(
            try await repository.playlists().first
        )
        #expect(updated.name == "Quiet Hours")
        #expect(updated.trackCount == 1)

        try await requireDeletedPlaylist(
            playlist.id,
            repository: repository,
            context: context
        )
    }

    @Test("Album playback follows disc and track numbers")
    func albumPlaybackOrder() async throws {
        let container = try makeContainer(
            titles: ["Third", "First", "Second"]
        )
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [SortDescriptor(\.normalizedTitle)]
            )
        )
        for record in records {
            record.trackNumber = switch record.title {
            case "First": 1
            case "Second": 2
            default: 3
            }
        }
        try context.save()
        let albumID = try #require(records.first?.album?.id)
        let repository = LibraryRepository(modelContainer: container)

        #expect(
            try await repository.albumTracksInPlaybackOrder(
                albumID: albumID
            ).map(\.title) == ["First", "Second", "Third"]
        )
    }

    @Test("All-track queue IDs use stable library order")
    func allTrackQueueOrder() async throws {
        let container = try makeContainer(
            titles: ["Zulu", "Alpha", "Echo"]
        )
        let context = ModelContext(container)
        let expected = try context.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [
                    SortDescriptor(\.normalizedTitle),
                    SortDescriptor(\.sortIdentity),
                ]
            )
        )
        .map(\.id)
        let repository = LibraryRepository(modelContainer: container)

        #expect(try await repository.allTrackIDs() == expected)
    }

    @Test("A stale playlist identity never becomes a successful no-op")
    func missingPlaylistFailsExplicitly() async throws {
        let container = try makeContainer(titles: ["Track"])
        let context = ModelContext(container)
        let trackID = try #require(
            try context.fetch(FetchDescriptor<TrackRecord>()).first?.id
        )
        let repository = LibraryRepository(modelContainer: container)
        let missingID = UUID()
        let expected = PlaylistRepositoryError.playlistNotFound(missingID)

        await #expect(throws: expected) {
            try await repository.playlistTracks(playlistID: missingID)
        }
        await #expect(throws: expected) {
            try await repository.renamePlaylist(id: missingID, name: "Missing")
        }
        await #expect(throws: expected) {
            try await repository.deletePlaylist(id: missingID)
        }
        await #expect(throws: expected) {
            try await repository.addToPlaylist(
                playlistID: missingID,
                trackIDs: [trackID]
            )
        }
        await #expect(throws: expected) {
            try await repository.removeFromPlaylist(
                playlistID: missingID,
                trackIDs: [trackID]
            )
        }
        await #expect(throws: expected) {
            try await repository.reorderPlaylist(
                playlistID: missingID,
                orderedTrackIDs: [trackID]
            )
        }
    }

    private func makeContainer(
        titles: [String]
    ) throws -> ModelContainer {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let session = ImportSessionRecord(
            sourceDisplayName: "Playlist Fixture",
            state: .complete,
            importedCount: titles.count
        )
        let artist = ArtistRecord(
            name: "Playlist Artist",
            trackCount: titles.count,
            albumCount: 1
        )
        let album = AlbumRecord(
            title: "Playlist Album",
            artist: artist,
            trackCount: titles.count,
            totalDuration: Double(titles.count) * 180
        )
        context.insert(session)
        context.insert(artist)
        context.insert(album)
        for (index, title) in titles.enumerated() {
            context.insert(
                TrackRecord(
                    originalFilename: "\(title).flac",
                    title: title,
                    duration: 180,
                    codec: "FLAC",
                    container: "FLAC",
                    sampleRate: 48000,
                    channelCount: 2,
                    contentHash: String(format: "%064x", index + 1),
                    relativeMediaPath: "Media/\(UUID().uuidString).flac",
                    importSessionID: session.id,
                    artist: artist,
                    album: album
                )
            )
        }
        try context.save()
        return container
    }

    private func requireDeletedPlaylist(
        _ id: UUID,
        repository: LibraryRepository,
        context: ModelContext
    ) async throws {
        try await repository.deletePlaylist(id: id)
        #expect(try await repository.playlists().isEmpty)
        #expect(
            try context.fetch(
                FetchDescriptor<PlaylistEntryRecord>()
            ).isEmpty
        )
    }
}
