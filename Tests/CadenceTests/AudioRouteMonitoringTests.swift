@testable import Cadence
import Foundation
import Testing

@MainActor
struct AudioRouteMonitoringTests {
    private let builtIn = AudioRouteSnapshot(
        name: "Mac Speakers",
        transport: .builtIn
    )
    private let wired = AudioRouteSnapshot(
        name: "Studio DAC",
        transport: .wired
    )
    private let airPlay = AudioRouteSnapshot(
        name: "Living Room",
        transport: .airPlay
    )

    @Test("Route monitoring lifecycle is idempotent")
    func monitoringLifecycle() {
        let provider = StaticAudioRouteProvider(route: builtIn)
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: []),
            backends: [],
            audioRouteProvider: provider
        )

        coordinator.activateSystemMediaSession()
        coordinator.activateSystemMediaSession()
        #expect(provider.monitoringStartCount == 1)

        coordinator.shutdown()
        coordinator.shutdown()
        #expect(provider.monitoringStopCount == 1)
    }

    @Test("Identical route notifications do not reload playback")
    func identicalRouteIsIgnored() async {
        let setup = makeStereoCoordinator(route: builtIn)
        await setup.start()

        setup.provider.emit(builtIn)
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.pcm.loadRequests.count == 1)
        #expect(setup.coordinator.outputRoute == builtIn)
    }

    @Test("AirPlay moves PCM playback to Native at the same time")
    func pcmToNative() async {
        let setup = makeStereoCoordinator(route: builtIn)
        await setup.start()
        setup.pcm.emit(.time(42))

        setup.provider.emit(airPlay)
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.coordinator.state.activeBackend == .native)
        #expect(setup.coordinator.state.currentTime == 42)
        #expect(setup.coordinator.state.isPlaying)
        #expect(setup.coordinator.outputRoute == airPlay)
        #expect(setup.coordinator.state.audioPath?.outputRoute == airPlay)
        #expect(setup.native.loadRequests.last?.startTime == 42)
        #expect(setup.native.loadRequests.last?.autoplay == true)
    }

    @Test("Returning from AirPlay moves Native playback back to PCM")
    func nativeToPCM() async {
        let setup = makeStereoCoordinator(route: airPlay)
        await setup.start()
        setup.native.emit(.time(31))

        setup.provider.emit(builtIn)
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.coordinator.state.activeBackend == .pcm)
        #expect(setup.coordinator.state.currentTime == 31)
        #expect(setup.coordinator.state.isPlaying)
        #expect(setup.coordinator.outputRoute == builtIn)
        #expect(setup.pcm.loadRequests.last?.startTime == 31)
        #expect(setup.pcm.loadRequests.last?.autoplay == true)
    }

    @Test("PCM route changes preserve the live engine and pause state")
    func pcmToPCM() async {
        let setup = makeStereoCoordinator(route: builtIn)
        await setup.start()
        setup.pcm.emit(.time(27))
        setup.coordinator.pause()

        setup.provider.emit(wired)
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.pcm.loadRequests.count == 1)
        #expect(setup.coordinator.state.transport == .paused)
        #expect(setup.coordinator.outputRoute == wired)
    }

    @Test("Native route changes keep the current item loaded")
    func nativeToNative() async {
        let setup = makeStereoCoordinator(route: airPlay)
        await setup.start()
        let secondAirPlay = AudioRouteSnapshot(
            name: "Bedroom",
            transport: .airPlay
        )

        setup.provider.emit(secondAirPlay)
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.native.loadRequests.count == 1)
        #expect(setup.coordinator.state.activeBackend == .native)
        #expect(setup.coordinator.outputRoute == secondAirPlay)
        #expect(
            setup.coordinator.state.audioPath?.outputRoute
                == secondAirPlay
        )
    }
}

extension AudioRouteMonitoringTests {
    @Test("Failed route activation pauses without skipping the track")
    func failedRouteTransition() async {
        let setup = makeStereoCoordinator(route: builtIn)
        await setup.start()
        setup.pcm.emit(.time(19))
        setup.native.loadError = PlaybackFailure(
            trackID: setup.track.track.id,
            message: "AirPlay unavailable"
        )

        setup.provider.emit(airPlay)
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.coordinator.state.transport == .paused)
        #expect(
            setup.coordinator.state.currentTrack?.id
                == setup.track.track.id
        )
        #expect(
            setup.coordinator.state.queue?.currentTrackID
                == setup.track.track.id
        )
        #expect(setup.coordinator.state.currentTime == 19)
        #expect(setup.coordinator.state.activeBackend == .pcm)
        #expect(setup.coordinator.outputRoute == builtIn)
        #expect(
            setup.coordinator.state.audioPath?.outputRoute
                == builtIn
        )
        #expect(
            setup.coordinator.state.failure?.message.contains(
                "new audio output"
            ) == true
        )
    }

    @Test("A valid route retries after failure and remains paused")
    func validRouteRetriesAfterFailure() async {
        let setup = makeStereoCoordinator(route: builtIn)
        await setup.start()
        setup.pcm.emit(.time(19))
        setup.native.loadError = PlaybackFailure(
            trackID: setup.track.track.id,
            message: "AirPlay unavailable"
        )
        setup.provider.emit(airPlay)
        await setup.coordinator.waitForAudioRouteTransitions()
        setup.native.loadError = nil

        setup.provider.emit(builtIn)
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.pcm.loadRequests.count == 1)
        #expect(setup.coordinator.state.transport == .paused)
        #expect(setup.coordinator.state.failure == nil)
    }

    @Test("Play retries the current system route after a route failure")
    func playRetriesFailedRoute() async {
        let setup = makeStereoCoordinator(route: builtIn)
        await setup.start()
        setup.pcm.emit(.time(23))
        setup.native.loadError = PlaybackFailure(
            trackID: setup.track.track.id,
            message: "AirPlay unavailable"
        )
        setup.provider.emit(airPlay)
        await setup.coordinator.waitForAudioRouteTransitions()
        setup.native.loadError = nil

        setup.coordinator.play()
        await setup.coordinator.waitForAudioRouteTransitions()
        await Task.yield()

        #expect(setup.coordinator.state.activeBackend == .native)
        #expect(setup.coordinator.state.currentTime == 23)
        #expect(setup.coordinator.state.isPlaying)
        #expect(setup.coordinator.outputRoute == airPlay)
        #expect(setup.native.loadRequests.last?.autoplay == false)
        #expect(setup.native.playCount == 1)
    }

    @Test("A missing required backend pauses and reports the route")
    func missingBackend() async {
        let track = playbackTestTrack(id: UUID(), title: "PCM Only")
        let provider = StaticAudioRouteProvider(route: builtIn)
        let pcm = PlaybackTestBackend(kind: .pcm)
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm],
            audioRouteProvider: provider
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [track.track.id]
        )

        provider.emit(airPlay)
        await coordinator.waitForAudioRouteTransitions()

        #expect(coordinator.state.transport == .paused)
        #expect(coordinator.state.currentTrack?.id == track.track.id)
        #expect(coordinator.outputRoute == builtIn)
        #expect(
            coordinator.state.failure?.message.contains(
                "No compatible playback backend"
            ) == true
        )
    }

    @Test("A newer route supersedes an unfinished transition")
    func newestRouteWins() async {
        let setup = makeStereoCoordinator(route: builtIn)
        await setup.start()
        setup.pcm.emit(.time(11))
        setup.native.shouldSuspendNextLoad = true

        setup.provider.emit(airPlay)
        await waitForSuspendedLoad(setup.native)
        setup.provider.emit(wired)
        setup.native.resumeNextLoad()
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.coordinator.outputRoute == wired)
        #expect(setup.coordinator.state.activeBackend == .pcm)
        #expect(setup.coordinator.state.currentTime == 11)
        #expect(setup.native.loadRequests.count == 1)
    }

    @Test("A new queue waits for an unfinished route transition")
    func newQueueSerializesAfterRouteTransition() async {
        let first = playbackTestTrack(id: UUID(), title: "First")
        let second = playbackTestTrack(id: UUID(), title: "Second")
        let provider = StaticAudioRouteProvider(route: builtIn)
        let pcm = PlaybackTestBackend(kind: .pcm)
        let native = PlaybackTestBackend(kind: .native)
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [first, second]),
            backends: [pcm, native],
            audioRouteProvider: provider
        )
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [first.track.id]
        )
        native.shouldSuspendNextLoad = true
        provider.emit(airPlay)
        await waitForSuspendedLoad(native)

        let newQueue = Task { @MainActor in
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [second.track.id]
            )
        }
        await Task.yield()
        native.resumeNextLoad()

        #expect(await newQueue.value)
        #expect(coordinator.state.currentTrack?.id == second.track.id)
        #expect(native.loadRequests.last?.current.track.id == second.track.id)
    }

    @Test("A route change without a loaded track updates the snapshot")
    func unloadedRouteChange() async {
        let provider = StaticAudioRouteProvider(route: builtIn)
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: []),
            backends: [],
            audioRouteProvider: provider
        )
        coordinator.activateSystemMediaSession()

        provider.emit(wired)
        await coordinator.waitForAudioRouteTransitions()

        #expect(coordinator.outputRoute == wired)
        #expect(coordinator.state.currentTrack == nil)
    }

    private func makeStereoCoordinator(
        route: AudioRouteSnapshot
    ) -> RouteMonitoringSetup {
        let track = playbackTestTrack(id: UUID(), title: "Route Test")
        let provider = StaticAudioRouteProvider(route: route)
        let pcm = PlaybackTestBackend(kind: .pcm)
        let native = PlaybackTestBackend(kind: .native)
        let coordinator = PlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm, native],
            audioRouteProvider: provider
        )
        return RouteMonitoringSetup(
            track: track,
            provider: provider,
            pcm: pcm,
            native: native,
            coordinator: coordinator
        )
    }

    private func waitForSuspendedLoad(
        _ backend: PlaybackTestBackend
    ) async {
        for _ in 0 ..< 20 where backend.suspendedLoadCount == 0 {
            await Task.yield()
        }
        #expect(backend.suspendedLoadCount == 1)
    }
}

@MainActor
private struct RouteMonitoringSetup {
    let track: ResolvedPlaybackTrack
    let provider: StaticAudioRouteProvider
    let pcm: PlaybackTestBackend
    let native: PlaybackTestBackend
    let coordinator: PlaybackCoordinator

    func start() async {
        let didStart = await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [track.track.id]
        )
        #expect(didStart)
    }
}
