@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibraryOperationFailureTests {
    @Test("A failed replacement keeps the last valid track page")
    func failedTrackReplacementPreservesData() async {
        let seededTrack = LibraryTrackProjection(
            id: UUID(),
            title: "Still Here",
            artistID: nil,
            artist: "Artist",
            albumID: nil,
            album: "Album",
            duration: 180,
            year: 2026,
            codec: "flac",
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            isFavorite: false,
            customArtworkID: nil,
            artworkID: nil,
            relativeMediaPath: "Media/still-here.flac",
            dateAdded: .now,
            lastPlayedAt: nil,
            playCount: 0,
            hasSynchronizedLyrics: false
        )
        let loader = FailingTrackPageLoader(track: seededTrack)
        let store = LibraryStore { query, cursor in
            try await loader.load(query: query, cursor: cursor)
        }

        await store.loadInitialTracks()
        await store.searchTracks("fails")

        #expect(store.tracks == [seededTrack])
        #expect(store.availability == .ready)
        #expect(store.operationFailure?.operation == .trackPage)

        await store.retryOperationFailure()

        #expect(store.tracks == [seededTrack])
        #expect(store.operationFailure == nil)
    }
}

private actor FailingTrackPageLoader {
    let track: LibraryTrackProjection
    var requestCount = 0

    init(track: LibraryTrackProjection) {
        self.track = track
    }

    func load(
        query _: LibraryTrackQuery,
        cursor _: LibraryPageCursor?
    ) throws -> LibraryPage<LibraryTrackProjection> {
        requestCount += 1
        if requestCount == 2 {
            throw Failure.expected
        }
        return LibraryPage(items: [track], nextCursor: nil)
    }

    private enum Failure: Error {
        case expected
    }
}
