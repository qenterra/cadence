@testable import Cadence
import Foundation
import Testing

struct HomeFavoriteRecencyTests {
    @Test("Home favorite tracks preserve most-recently-added order")
    func mostRecentlyAddedTracksComeFirst() throws {
        let suite = "HomeFavoriteTrackRecency.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = track(title: "First")
        let second = track(title: "Second")
        let third = track(title: "Third")

        HomeFavoriteRecencyStore.recordTrack(
            third.id,
            isFavorite: true,
            defaults: defaults
        )
        HomeFavoriteRecencyStore.recordTrack(
            first.id,
            isFavorite: true,
            defaults: defaults
        )

        #expect(
            HomeFavoriteRecencyStore.orderedTracks(
                [first, second, third],
                defaults: defaults
            ).map(\.id) == [first.id, third.id, second.id]
        )
    }

    private func track(title: String) -> LibraryTrackProjection {
        LibraryTrackProjection(
            id: UUID(),
            title: title,
            artistID: nil,
            artist: "Artist",
            albumID: nil,
            album: "Album",
            duration: 180,
            year: 2026,
            codec: "flac",
            sampleRate: 44100,
            channelCount: 2,
            bitDepth: 24,
            isFavorite: true,
            customArtworkID: nil,
            artworkID: nil,
            relativeMediaPath: "\(UUID()).flac",
            lastPlayedAt: nil,
            hasSynchronizedLyrics: false
        )
    }
}
