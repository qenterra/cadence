@testable import Cadence
import Foundation
import Testing

@MainActor
struct PlaybackQueueCoordinatorTests {
    @Test("Queue editing changes only the coordinator snapshot")
    func queueEditing() async {
        let tracks = (0 ..< 4).map {
            playbackTestTrack(id: UUID(), title: "Track \($0)")
        }
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [PlaybackTestBackend(kind: .pcm)]
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: tracks.map(\.track.id)
        )

        let didReorder = coordinator.reorderUpNext(
            [tracks[3].track.id],
            before: tracks[1].track.id
        )

        #expect(didReorder)
        #expect(coordinator.state.queue?.orderedTrackIDs == [
            tracks[0].track.id,
            tracks[3].track.id,
            tracks[1].track.id,
            tracks[2].track.id,
        ])
        #expect(coordinator.state.currentTrack?.id == tracks[0].track.id)
    }

    @Test("Playing a queue row uses the normal load pipeline")
    func playQueueItem() async {
        let tracks = (0 ..< 4).map {
            playbackTestTrack(id: UUID(), title: "Track \($0)")
        }
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [backend]
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: tracks.map(\.track.id)
        )

        let didPlay = await coordinator.playQueueItem(
            id: tracks[2].track.id
        )
        #expect(didPlay)
        #expect(coordinator.state.currentTrack?.id == tracks[2].track.id)
        #expect(coordinator.state.queue?.orderedTrackIDs == tracks.map(\.track.id))
        #expect(coordinator.state.queue?.previouslyPlayedTrackIDs == [
            tracks[0].track.id,
            tracks[1].track.id,
        ])
        #expect(backend.loadRequests.count == 2)
        #expect(backend.loadRequests.last?.startTime == 0)
        let didPlayMissing = await coordinator.playQueueItem(id: UUID())
        #expect(!didPlayMissing)
    }

    @Test("Restoring an edited queue preserves transport and position")
    func restoreEditedQueue() async {
        let tracks = (0 ..< 4).map {
            playbackTestTrack(id: UUID(), title: "Track \($0)")
        }
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [PlaybackTestBackend(kind: .pcm)]
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: tracks.map(\.track.id),
            startingAt: tracks[1].track.id
        )
        coordinator.receive(.time(37), from: .pcm)
        let original = coordinator.state.queue
        _ = coordinator.removeUpNext([tracks[2].track.id])

        let didRestore = original.map(
            coordinator.restoreQueueSnapshot
        ) ?? false

        #expect(didRestore)
        #expect(coordinator.state.queue == original)
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)
        #expect(coordinator.state.currentTime == 37)
        #expect(coordinator.isPlaying)
    }
}
