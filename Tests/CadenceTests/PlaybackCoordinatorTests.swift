@testable import Cadence
import Foundation
import Testing

@MainActor
struct PlaybackCoordinatorTests {
    @Test("Queue start, pause, play, seek, next, and previous share one state")
    func transport() async {
        let tracks = [
            playbackTestTrack(id: UUID(), title: "One"),
            playbackTestTrack(id: UUID(), title: "Two"),
            playbackTestTrack(id: UUID(), title: "Three"),
        ]
        let resolver = PlaybackTestResolver(tracks: tracks)
        let pcm = PlaybackTestBackend(kind: .pcm)
        let native = PlaybackTestBackend(kind: .native)
        let media = PlaybackTestSystemMediaSession()
        let coordinator = PlaybackCoordinator(
            resolver: resolver,
            backends: [pcm, native],
            systemMediaSession: media
        )

        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: tracks.map(\.track.id),
                startingAt: tracks[0].track.id
            )
        )
        #expect(coordinator.state.currentTrack?.id == tracks[0].track.id)
        #expect(coordinator.state.isPlaying)
        #expect(pcm.loadRequests.count == 1)
        #expect(pcm.loadRequests[0].next?.track.id == tracks[1].track.id)

        coordinator.pause()
        #expect(!coordinator.state.isPlaying)
        coordinator.play()
        #expect(coordinator.state.isPlaying)

        await coordinator.seek(to: 30)
        #expect(coordinator.state.currentTime == 30)
        #expect(pcm.seekTimes == [30])

        await coordinator.next()
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)
        await coordinator.previous()
        #expect(coordinator.state.currentTrack?.id == tracks[0].track.id)
        #expect(media.activationCount == 1)
    }

    @Test("Backend time is the canonical progress source")
    func canonicalProgress() async {
        let track = playbackTestTrack(
            id: UUID(),
            title: "Progress",
            duration: 200
        )
        let resolver = PlaybackTestResolver(tracks: [track])
        let pcm = PlaybackTestBackend(kind: .pcm)
        let coordinator = PlaybackCoordinator(
            resolver: resolver,
            backends: [pcm]
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [track.track.id]
        )

        pcm.emit(.time(50))

        #expect(coordinator.state.currentTime == 50)
        #expect(coordinator.progress == 0.25)
    }

    @Test("Repeat one reloads the current track at completion")
    func repeatOne() async {
        let tracks = [
            playbackTestTrack(id: UUID(), title: "One"),
            playbackTestTrack(id: UUID(), title: "Two"),
        ]
        let pcm = PlaybackTestBackend(kind: .pcm)
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [pcm]
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: tracks.map(\.track.id)
        )
        coordinator.repeatMode = .one

        pcm.emit(
            .finished(
                trackID: tracks[0].track.id,
                successorStarted: nil
            )
        )
        await Task.yield()
        await Task.yield()

        #expect(coordinator.state.currentTrack?.id == tracks[0].track.id)
        #expect(pcm.loadRequests.count == 2)
        #expect(pcm.loadRequests.last?.startTime == 0)
    }

    @Test("Unavailable tracks wait for an explicit Retry or Skip")
    func unavailable() async {
        let tracks = [
            playbackTestTrack(id: UUID(), title: "Missing"),
            playbackTestTrack(id: UUID(), title: "Playable"),
        ]
        let resolver = PlaybackTestResolver(tracks: tracks)
        resolver.unavailableIDs = [tracks[0].track.id]
        let native = PlaybackTestBackend(kind: .native)
        let coordinator = PlaybackCoordinator(
            resolver: resolver,
            backends: [native]
        )

        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: tracks.map(\.track.id)
        )

        #expect(coordinator.state.queue?.currentTrackID == tracks[0].track.id)
        #expect(coordinator.state.failure != nil)
        #expect(coordinator.state.transport == .failed)
        #expect(native.loadRequests.isEmpty)

        resolver.unavailableIDs = []
        #expect(await coordinator.retryFailedCurrent())
        #expect(coordinator.state.currentTrack?.id == tracks[0].track.id)
        #expect(coordinator.state.failure == nil)

        coordinator.failCurrent(
            with: PlaybackFailure(
                trackID: tracks[0].track.id,
                message: "Failed again"
            )
        )
        await coordinator.skipFailedTrack()
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)
    }

    @Test("System media commands forward exactly once")
    func systemCommands() async {
        let track = playbackTestTrack(id: UUID(), title: "Remote")
        let backend = PlaybackTestBackend(kind: .pcm)
        let media = PlaybackTestSystemMediaSession()
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [backend],
            systemMediaSession: media
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [track.track.id]
        )

        media.send(.pause)
        media.send(.play)
        media.send(.changePosition(42))
        await Task.yield()

        #expect(backend.pauseCount == 1)
        #expect(backend.playCount == 1)
        #expect(backend.seekTimes == [42])
    }

    @Test("System media registration remains idempotent")
    func systemRegistration() {
        let media = PlaybackTestSystemMediaSession()
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: []),
            backends: [],
            systemMediaSession: media
        )

        coordinator.activateSystemMediaSession()
        coordinator.activateSystemMediaSession()

        #expect(media.activationCount == 1)
    }

    @Test("Final playback failure remains visible")
    func terminalFailure() async {
        let track = playbackTestTrack(id: UUID(), title: "Missing")
        let resolver = PlaybackTestResolver(tracks: [track])
        resolver.unavailableIDs = [track.track.id]
        let coordinator = PlaybackCoordinator(
            resolver: resolver,
            backends: [PlaybackTestBackend(kind: .pcm)]
        )

        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [track.track.id]
        )

        #expect(coordinator.state.transport == .failed)
        #expect(coordinator.state.failure?.trackID == track.track.id)
        #expect(coordinator.state.failure?.message == "Unavailable")
    }

    @Test("A silent PCM start is rescheduled once before Playing")
    func silentPCMStartRetriesOnce() async {
        let track = playbackTestTrack(id: UUID(), title: "Retry")
        let backend = PlaybackTestBackend(kind: .pcm)
        backend.startObservations = [
            .failed(.renderDidNotAdvance),
            .started,
        ]
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [backend]
        )

        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [track.track.id]
            )
        )

        #expect(backend.loadRequests.count == 2)
        #expect(backend.stopCount == 2)
        #expect(coordinator.state.currentTrack?.id == track.track.id)
        #expect(coordinator.state.transport == .playing)
    }

    @Test("A second silent PCM start pauses on the same track for Retry")
    func repeatedSilentPCMStartPauses() async {
        let track = playbackTestTrack(id: UUID(), title: "Silent")
        let backend = PlaybackTestBackend(kind: .pcm)
        backend.startObservations = [
            .failed(.renderDidNotAdvance),
            .failed(.renderDidNotAdvance),
        ]
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [backend]
        )

        #expect(
            await !(coordinator.startQueue(
                source: .adHoc,
                trackIDs: [track.track.id]
            ))
        )

        #expect(backend.loadRequests.count == 2)
        #expect(coordinator.state.currentTrack?.id == track.track.id)
        #expect(coordinator.state.transport == .paused)
        #expect(coordinator.state.failure?.kind == .silentStart)

        coordinator.play()

        #expect(coordinator.state.transport == .paused)
        #expect(backend.playCount == 0)
    }
}
