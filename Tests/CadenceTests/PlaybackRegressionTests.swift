@testable import Cadence
import Foundation
import Testing

@MainActor
struct PlaybackRegressionTests {
    @Test("Timeline bursts do not republish the whole playback state")
    func throttledTimelinePublication() async {
        let track = playbackTestTrack(
            id: UUID(),
            title: "Quiet UI",
            duration: 200
        )
        let pcm = PlaybackTestBackend(kind: .pcm)
        let media = PlaybackTestSystemMediaSession()
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm],
            systemMediaSession: media
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [track.track.id]
        )
        let baselinePublications = media.states.count

        for tick in 0 ..< 8 {
            pcm.emit(
                .timeline(
                    PlaybackTimelineSample(
                        mediaTime: 20 + Double(tick) / 10,
                        hostUptime: 100 + Double(tick) / 10,
                        rate: 1
                    )
                )
            )
        }

        #expect(media.states.count == baselinePublications + 1)
        #expect(
            abs(coordinator.presentationTime(atHostUptime: 100.8) - 20.8)
                < 0.001
        )
    }

    @Test("Presentation time follows timestamped backend rate changes")
    func presentationClock() async {
        let track = playbackTestTrack(id: UUID(), title: "Clock", duration: 200)
        let pcm = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm]
        )
        await coordinator.startQueue(source: .adHoc, trackIDs: [track.track.id])
        pcm.emit(
            .timeline(
                PlaybackTimelineSample(
                    mediaTime: 40,
                    hostUptime: 100,
                    rate: 1
                )
            )
        )

        #expect(
            abs(
                coordinator.presentationTime(
                    atHostUptime: 100.2
                ) - 40.2
            ) < 0.001
        )

        pcm.emit(
            .timeline(
                PlaybackTimelineSample(
                    mediaTime: 40.2,
                    hostUptime: 100.2,
                    rate: 0
                )
            )
        )
        #expect(
            coordinator.presentationTime(
                atHostUptime: 101
            ) == 40.2
        )
    }

    @Test("A stale backend cannot replace the active presentation timeline")
    func staleBackendTimeline() async {
        let track = playbackTestTrack(id: UUID(), title: "Clock", duration: 200)
        let pcm = PlaybackTestBackend(kind: .pcm)
        let native = PlaybackTestBackend(kind: .native)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm, native]
        )
        await coordinator.startQueue(source: .adHoc, trackIDs: [track.track.id])
        pcm.emit(
            .timeline(
                PlaybackTimelineSample(
                    mediaTime: 40,
                    hostUptime: 100,
                    rate: 1
                )
            )
        )

        native.emit(
            .timeline(
                PlaybackTimelineSample(
                    mediaTime: 99,
                    hostUptime: 101,
                    rate: 1
                )
            )
        )

        #expect(coordinator.state.currentTime == 40)
        #expect(
            coordinator.presentationTime(
                atHostUptime: 101
            ) == 41
        )
    }

    @Test("Progress callbacks do not mutate the lightweight row indicator")
    func stablePlaybackIndicator() async {
        let track = playbackTestTrack(id: UUID(), title: "Indicator")
        let pcm = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm]
        )
        await coordinator.startQueue(source: .adHoc, trackIDs: [track.track.id])
        let indicator = coordinator.playbackIndicator

        pcm.emit(.time(12))

        #expect(coordinator.playbackIndicator == indicator)
    }
}
