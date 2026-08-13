@testable import Cadence
import Foundation
import Testing

@MainActor
struct PlaybackVolumeTests {
    @Test("Volume changes clamp once and reach the active backend")
    func volumeChanges() async {
        let track = playbackTestTrack(id: UUID(), title: "Volume")
        let pcm = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm]
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [track.track.id]
        )

        coordinator.setVolume(1.5)
        coordinator.setVolume(-0.5)
        coordinator.setVolume(0.5)
        coordinator.setVolume(0.5)

        #expect(coordinator.volume == 0.5)
        #expect(pcm.volumes == [1, 0, 0.5])
    }
}
