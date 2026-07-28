@testable import Cadence
import Foundation
import Testing

@MainActor
struct ProductionPlaybackAppModelTests {
    @Test("Production app state reflects the real coordinator")
    func stateBridge() async {
        let resolved = [
            playbackTestTrack(id: UUID(), title: "One"),
            playbackTestTrack(id: UUID(), title: "Two"),
        ]
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: resolved),
            backends: [PlaybackTestBackend(kind: .pcm)]
        )
        let model = CadenceAppModel(
            librarySession: .preview(),
            tracks: [],
            tags: [],
            tagAssignments: [],
            tagExclusions: [],
            smartCollections: [],
            lyricDocuments: [:],
            favoriteAlbumDates: [:],
            favoriteArtistDates: [:],
            importCandidates: [],
            playbackCoordinator: coordinator
        )

        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: resolved.map(\.track.id)
        )

        #expect(model.currentPlaybackTrack?.id == resolved[0].track.id)
        #expect(model.isPlaying)
        #expect(model.progress == 0)

        coordinator.receive(.time(30), from: .pcm)
        #expect(model.playbackCurrentTime == 30)
        #expect(
            model.progress
                == 30 / resolved[0].track.duration
        )
    }

    @Test("Committed production seek keeps the requested progress")
    func committedSeek() async {
        let resolved = playbackTestTrack(
            id: UUID(),
            title: "Seek",
            duration: 200
        )
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [resolved]),
            backends: [backend]
        )
        let model = CadenceAppModel(
            librarySession: .preview(),
            tracks: [],
            tags: [],
            tagAssignments: [],
            tagExclusions: [],
            smartCollections: [],
            lyricDocuments: [:],
            favoriteAlbumDates: [:],
            favoriteArtistDates: [:],
            importCandidates: [],
            playbackCoordinator: coordinator
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [resolved.track.id]
        )

        await model.seekPlayback(toProgress: 0.4)

        #expect(backend.seekTimes == [80])
        #expect(model.playbackCurrentTime == 80)
        #expect(model.progress == 0.4)
    }
}
