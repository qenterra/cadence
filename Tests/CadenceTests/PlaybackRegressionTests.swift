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
        let coordinator = PlaybackCoordinator(
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
        let coordinator = PlaybackCoordinator(
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
        let coordinator = PlaybackCoordinator(
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

    @Test("Changing Adaptive to Pure updates PCM ReplayGain without changing tracks")
    func sameBackendProfileReload() async {
        let track = playbackTestTrack(
            id: UUID(),
            title: "Gain",
            replayGainTrackGain: -7
        )
        let pcm = PlaybackTestBackend(kind: .pcm)
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm]
        )
        await coordinator.startQueue(source: .adHoc, trackIDs: [track.track.id])

        await coordinator.setQualityProfile(.pure)

        #expect(pcm.loadRequests.count == 1)
        #expect(pcm.loadRequests[0].replayGainDecibels == -7)
        #expect(pcm.replayGains.count == 1)
        #expect(pcm.replayGains[0] == nil)
        #expect(coordinator.state.activeBackend == .pcm)
        #expect(coordinator.qualityProfile == .pure)
    }

    @Test("Progress callbacks do not mutate the lightweight row indicator")
    func stablePlaybackIndicator() async {
        let track = playbackTestTrack(id: UUID(), title: "Indicator")
        let pcm = PlaybackTestBackend(kind: .pcm)
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm]
        )
        await coordinator.startQueue(source: .adHoc, trackIDs: [track.track.id])
        let indicator = coordinator.playbackIndicator

        pcm.emit(.time(12))

        #expect(coordinator.playbackIndicator == indicator)
    }

    @Test("A newer quality choice supersedes an unfinished backend switch")
    func rapidQualityChanges() async {
        let track = playbackTestTrack(id: UUID(), title: "Rapid")
        let pcm = PlaybackTestBackend(kind: .pcm)
        let native = PlaybackTestBackend(kind: .native)
        native.shouldSuspendNextLoad = true
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm, native]
        )
        await coordinator.startQueue(source: .adHoc, trackIDs: [track.track.id])
        coordinator.stereoSpatializationEnabled = true

        let immersive = Task {
            await coordinator.setQualityProfile(.immersive)
        }
        while native.suspendedLoadCount == 0 {
            await Task.yield()
        }
        let pure = Task {
            await coordinator.setQualityProfile(.pure)
        }
        await Task.yield()
        native.resumeNextLoad()
        await immersive.value
        await pure.value

        #expect(coordinator.qualityProfile == .pure)
        #expect(coordinator.state.activeBackend == .pcm)
        #expect(coordinator.state.isPlaying)
        #expect(pcm.playCount == 0)
        #expect(native.stopCount >= 1)
    }

    @Test("Leaving Immersive cancels an unfinished native backend switch")
    func cancelUnfinishedImmersiveSwitch() async {
        let track = playbackTestTrack(id: UUID(), title: "Responsive")
        let pcm = PlaybackTestBackend(kind: .pcm)
        let native = PlaybackTestBackend(kind: .native)
        native.loadDelay = .seconds(30)
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm, native]
        )
        await coordinator.startQueue(source: .adHoc, trackIDs: [track.track.id])
        coordinator.stereoSpatializationEnabled = true

        let immersive = Task {
            await coordinator.setQualityProfile(.immersive)
        }
        while native.loadRequests.isEmpty {
            await Task.yield()
        }
        #expect(pcm.pauseCount == 0)
        var pureCompleted = false
        let pure = Task {
            await coordinator.setQualityProfile(.pure)
            pureCompleted = true
        }

        try? await Task.sleep(for: .milliseconds(100))

        #expect(pureCompleted)
        #expect(coordinator.qualityProfile == .pure)
        #expect(coordinator.state.activeBackend == .pcm)
        #expect(coordinator.state.isPlaying)

        coordinator.stop()
        await immersive.value
        await pure.value
    }
}
