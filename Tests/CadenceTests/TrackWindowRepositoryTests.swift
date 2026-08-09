@testable import Cadence
import Foundation
import SwiftData
import Testing

struct TrackWindowRepositoryTests {
    @Test("A virtual track window fetches only the requested offset range")
    func trackWindow() async throws {
        let container = try makeContainer(trackCount: 205)
        let repository = LibraryRepository(modelContainer: container)

        let tracks = try await repository.tracksWindow(
            query: .allTracks,
            offset: 192,
            limit: 64
        )

        #expect(tracks.count == 13)
        #expect(tracks.first?.title == "Track 192")
        #expect(tracks.last?.title == "Track 204")
    }

    private func makeContainer(trackCount: Int) throws -> ModelContainer {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let importID = UUID()
        let artist = ArtistRecord(name: "Window Artist")
        let album = AlbumRecord(title: "Window Album", artist: artist)
        let session = ImportSessionRecord(
            id: importID,
            sourceDisplayName: "Fixture",
            state: .complete
        )
        context.insert(artist)
        context.insert(album)
        context.insert(session)

        for index in 0 ..< trackCount {
            let title = "Track \(String(format: "%03d", index))"
            let trackID = UUID()
            context.insert(
                TrackRecord(
                    id: trackID,
                    originalFilename: "\(title).flac",
                    title: title,
                    duration: 180,
                    codec: "FLAC",
                    container: "FLAC",
                    sampleRate: 48000,
                    channelCount: 2,
                    contentHash: String(format: "%064x", index + 1),
                    relativeMediaPath: "Media/\(trackID.uuidString).flac",
                    importSessionID: importID,
                    artist: artist,
                    album: album
                )
            )
        }
        try context.save()
        return container
    }
}
