@testable import Cadence
import Foundation
@testable import QenTerraAudioAnalysis
import Testing

@MainActor
struct SingleTrackShuffleRegressionTests {
    @Test("Repeat all does not preload a one-track queue as its own successor")
    func repeatAllSingleTrackDoesNotDuplicateResolution() async {
        let track = playbackTestTrack(
            id: UUID(),
            title: "Single Track Album"
        )
        let resolver = PlaybackTestResolver(tracks: [track])
        let pcm = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: resolver,
            backends: [pcm]
        )
        coordinator.repeatMode = .all

        #expect(
            await coordinator.startQueue(
                source: .album(UUID()),
                trackIDs: [track.track.id],
                isShuffled: true
            )
        )

        #expect(resolver.requests == [[track.track.id]])
        #expect(pcm.preparedTracks.last == nil)
    }
}
