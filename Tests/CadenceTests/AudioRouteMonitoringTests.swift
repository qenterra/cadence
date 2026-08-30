import AVFoundation
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

    @Test("AirPlay routing falls back to the system while Native is empty")
    func emptyNativePlayerUsesSystemRouting() {
        let player = AVPlayer()

        #expect(AirPlayRoutePicker.routingPlayer(player) == nil)
    }

    @Test("AirPlay routing follows Native once it has playable content")
    func loadedNativePlayerUsesPlayerRouting() {
        let player = AVPlayer(
            playerItem: AVPlayerItem(
                url: URL(filePath: "/tmp/cadence-airplay-test.m4a")
            )
        )

        #expect(AirPlayRoutePicker.routingPlayer(player) === player)
    }

    @Test("Route monitoring lifecycle is idempotent")
    func monitoringLifecycle() {
        let provider = PlaybackTestAudioRouteProvider(route: builtIn)
        let coordinator = makePlaybackCoordinator(
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
        setup.pcm.bassMeter.store(0.5)
        let bassResetCount = setup.pcm.resetBassCount

        setup.provider.emit(builtIn)
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.pcm.loadRequests.count == 1)
        #expect(setup.coordinator.outputRoute == builtIn)
        #expect(setup.pcm.resetBassCount == bassResetCount)
        #expect(setup.coordinator.currentBassLevel() == 0.5)
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
        #expect(setup.native.loadRequests.last?.autoplay == false)
        #expect(setup.native.playCount == 1)
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
        #expect(setup.pcm.loadRequests.last?.autoplay == false)
        #expect(setup.pcm.playCount == 1)
    }

    @Test("PCM route changes preserve the live engine and pause state")
    func pcmToPCM() async {
        let setup = makeStereoCoordinator(route: builtIn)
        await setup.start()
        setup.pcm.emit(.time(27))
        setup.coordinator.pause()
        let bassResetCount = setup.pcm.resetBassCount

        setup.provider.emit(wired)
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.pcm.loadRequests.count == 1)
        #expect(setup.coordinator.state.transport == .paused)
        #expect(setup.coordinator.outputRoute == wired)
        #expect(setup.pcm.resetBassCount > bassResetCount)
    }

    @Test("PCM route reset rejects a callback from the previous publication epoch")
    func pcmRouteResetFencesStaleBassPublication() async {
        let setup = makeStereoCoordinator(route: builtIn)
        await setup.start()
        let staleEpoch = setup.pcm.bassMeter.publicationEpoch()

        setup.provider.emit(wired)
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.coordinator.state.transport == .playing)
        #expect(setup.coordinator.outputRoute == wired)
        #expect(
            !setup.pcm.bassMeter.store(
                0.95,
                ifPublicationEpoch: staleEpoch
            )
        )
        #expect(setup.coordinator.currentBassLevel() == 0)

        let activeEpoch = setup.pcm.bassMeter.publicationEpoch()
        #expect(
            setup.pcm.bassMeter.store(
                0.45,
                ifPublicationEpoch: activeEpoch
            )
        )
        #expect(setup.coordinator.currentBassLevel() == 0.45)
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
    @Test("Pause wins while a PCM to Native route load is suspended")
    func pauseDuringPCMToNativeTransition() async {
        let setup = makeStereoCoordinator(route: builtIn)
        await setup.start()
        setup.native.simulatesAutoplayDuringLoad = true
        setup.native.shouldSuspendNextLoad = true

        setup.provider.emit(airPlay)
        await waitForSuspendedLoad(setup.native)
        #expect(setup.native.loadRequests.first?.autoplay == false)
        #expect(setup.native.loadAutoplayStartCount == 0)
        #expect(setup.native.playCount == 0)
        setup.coordinator.pause()
        setup.native.shouldSuspendNextLoad = true
        setup.native.resumeNextLoad()
        await waitForSuspendedLoad(setup.native, count: 2)
        #expect(setup.native.loadRequests.allSatisfy { !$0.autoplay })
        #expect(setup.native.loadAutoplayStartCount == 0)
        #expect(setup.native.playCount == 0)
        setup.native.resumeNextLoad()
        await setup.coordinator.waitForAudioRouteTransitions()
        setup.native.bassMeter.store(0.9)

        #expect(setup.native.loadRequests.count == 2)
        #expect(setup.native.stopCount >= 1)
        #expect(setup.native.playCount == 0)
        #expect(setup.coordinator.state.transport == .paused)
        #expect(setup.coordinator.state.activeBackend == .native)
        #expect(setup.coordinator.outputRoute == airPlay)
        #expect(setup.coordinator.currentBassLevel() == 0)
    }

    @Test("Play wins while a Native to PCM route load is suspended")
    func playDuringNativeToPCMTransition() async {
        let setup = makeStereoCoordinator(route: airPlay)
        await setup.start()
        setup.coordinator.pause()
        setup.pcm.simulatesAutoplayDuringLoad = true
        setup.pcm.shouldSuspendNextLoad = true

        setup.provider.emit(builtIn)
        await waitForSuspendedLoad(setup.pcm)
        #expect(setup.pcm.loadRequests.first?.autoplay == false)
        #expect(setup.pcm.loadAutoplayStartCount == 0)
        #expect(setup.pcm.playCount == 0)
        setup.coordinator.play()
        setup.pcm.shouldSuspendNextLoad = true
        setup.pcm.resumeNextLoad()
        await waitForSuspendedLoad(setup.pcm, count: 2)
        #expect(setup.pcm.loadRequests.allSatisfy { !$0.autoplay })
        #expect(setup.pcm.loadAutoplayStartCount == 0)
        #expect(setup.pcm.playCount == 0)
        setup.pcm.resumeNextLoad()
        await setup.coordinator.waitForAudioRouteTransitions()
        setup.pcm.bassMeter.store(0.65)

        #expect(setup.pcm.loadRequests.count == 2)
        #expect(setup.pcm.stopCount >= 1)
        #expect(setup.pcm.playCount == 1)
        #expect(setup.coordinator.state.transport == .playing)
        #expect(setup.coordinator.state.activeBackend == .pcm)
        #expect(setup.coordinator.outputRoute == builtIn)
        #expect(setup.coordinator.currentBassLevel() == 0.65)
    }

    @Test("Gapless adoption retries a suspended route for the successor")
    func gaplessSuccessorDuringSuspendedRouteTransition() async {
        let tracks = [
            playbackTestTrack(id: UUID(), title: "First"),
            playbackTestTrack(id: UUID(), title: "Second"),
        ]
        let provider = PlaybackTestAudioRouteProvider(route: builtIn)
        let pcm = PlaybackTestBackend(kind: .pcm)
        let native = PlaybackTestBackend(kind: .native)
        let bassEnvelopeLoader = PlaybackTestBassEnvelopeLoader()
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [pcm, native],
            audioRouteProvider: provider,
            bassEnvelopeLoader: { url in
                await bassEnvelopeLoader.load(url)
            }
        )
        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: tracks.map(\.track.id)
            )
        )
        native.simulatesAutoplayDuringLoad = true
        native.shouldSuspendNextLoad = true

        provider.emit(airPlay)
        await waitForSuspendedLoad(native)
        #expect(native.loadRequests.first?.autoplay == false)
        #expect(native.loadAutoplayStartCount == 0)
        #expect(native.playCount == 0)
        pcm.emit(
            .finished(
                trackID: tracks[0].track.id,
                successorStarted: tracks[1].track.id
            )
        )
        for _ in 0 ..< 20
            where coordinator.state.currentTrack?.id != tracks[1].track.id {
            await Task.yield()
        }
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)

        native.shouldSuspendNextLoad = true
        native.resumeNextLoad()
        await waitForSuspendedLoad(native, count: 2)
        #expect(native.loadRequests.allSatisfy { !$0.autoplay })
        #expect(native.loadAutoplayStartCount == 0)
        #expect(native.playCount == 0)
        native.resumeNextLoad()
        await coordinator.waitForAudioRouteTransitions()
        let receivedBassRequest = await waitForBassEnvelopeRequests(
            1,
            loader: bassEnvelopeLoader
        )
        #expect(receivedBassRequest)
        guard receivedBassRequest else {
            return
        }
        #expect(
            await bassEnvelopeLoader.requestedURLs.last
                == tracks[1].mediaURL
        )
        await bassEnvelopeLoader.resumeNext(
            with: playbackTestBassEnvelope(level: 0.55)
        )
        #expect(
            await waitForBassLevel(0.55, coordinator: coordinator)
        )

        #expect(native.loadRequests.count == 2)
        #expect(native.loadRequests.first?.current.track.id == tracks[0].track.id)
        #expect(native.loadRequests.last?.current.track.id == tracks[1].track.id)
        #expect(coordinator.state.queue?.currentTrackID == tracks[1].track.id)
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)
        #expect(coordinator.state.transport == .playing)
        #expect(coordinator.state.activeBackend == .native)
        #expect(coordinator.outputRoute == airPlay)
        #expect(coordinator.currentBassLevel() == 0.55)
        #expect(native.playCount == 1)
    }

    @Test("PCM to Native starts fallback only after route commit")
    func pcmToNativeBassCommitOrdering() async {
        let loader = PlaybackTestBassEnvelopeLoader()
        let setup = makeStereoCoordinator(
            route: builtIn,
            bassEnvelopeLoader: { url in await loader.load(url) }
        )
        await setup.start()
        setup.pcm.bassMeter.store(0.8)
        setup.native.shouldSuspendNextLoad = true

        setup.provider.emit(airPlay)
        await waitForSuspendedLoad(setup.native)
        let precommitRequestCount = await loader.requestCount()
        #expect(precommitRequestCount == 0)
        #expect(setup.coordinator.currentBassLevel() == 0)

        setup.native.resumeNextLoad()
        await setup.coordinator.waitForAudioRouteTransitions()
        let received = await waitForBassEnvelopeRequests(1, loader: loader)
        #expect(received)
        guard received else {
            return
        }
        #expect(setup.coordinator.state.activeBackend == .native)

        await loader.resumeNext(
            with: playbackTestBassEnvelope(level: 0.7)
        )
        let accepted = await waitForBassLevel(
            0.7,
            coordinator: setup.coordinator
        )
        #expect(accepted)
    }

    @Test("Native to PCM rejects fallback and selects realtime provider")
    func nativeToPCMBassSource() async {
        let loader = PlaybackTestBassEnvelopeLoader()
        let setup = makeStereoCoordinator(
            route: airPlay,
            bassEnvelopeLoader: { url in await loader.load(url) }
        )
        await setup.start()
        let received = await waitForBassEnvelopeRequests(1, loader: loader)
        #expect(received)
        guard received else {
            return
        }
        await loader.resumeNext(
            with: playbackTestBassEnvelope(level: 0.8)
        )
        let accepted = await waitForBassLevel(
            0.8,
            coordinator: setup.coordinator
        )
        #expect(accepted)

        setup.provider.emit(builtIn)
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.coordinator.state.activeBackend == .pcm)
        #expect(setup.coordinator.bassEnvelope == nil)
        #expect(setup.coordinator.currentBassLevel() == 0)
        setup.pcm.bassMeter.store(0.45)
        #expect(setup.coordinator.currentBassLevel() == 0.45)
    }

    @Test("Failed and superseded Native routes leave bass at zero")
    func rejectedNativeRoutesStaySilent() async {
        let loader = PlaybackTestBassEnvelopeLoader()
        let setup = makeStereoCoordinator(
            route: builtIn,
            bassEnvelopeLoader: { url in await loader.load(url) }
        )
        await setup.start()
        setup.pcm.bassMeter.store(0.9)
        setup.native.loadError = PlaybackFailure(
            trackID: setup.track.track.id,
            message: "Unavailable"
        )

        setup.provider.emit(airPlay)
        await setup.coordinator.waitForAudioRouteTransitions()
        #expect(setup.coordinator.currentBassLevel() == 0)
        let failedRequestCount = await loader.requestCount()
        #expect(failedRequestCount == 0)

        setup.native.loadError = nil
        setup.native.shouldSuspendNextLoad = true
        setup.provider.emit(airPlay)
        await waitForSuspendedLoad(setup.native)
        setup.provider.emit(wired)
        setup.native.resumeNextLoad()
        await setup.coordinator.waitForAudioRouteTransitions()

        #expect(setup.coordinator.state.activeBackend == .pcm)
        #expect(setup.coordinator.currentBassLevel() == 0)
        let supersededRequestCount = await loader.requestCount()
        #expect(supersededRequestCount == 0)
    }

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

    @Test("A valid route remains paused after failure when auto-resume is off")
    func validRouteRetriesAfterFailure() async throws {
        let suite = "AudioRouteMonitoringTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            false,
            forKey: CadencePreferences.Keys.resumesAfterRouteRecovery
        )
        let setup = makeStereoCoordinator(
            route: builtIn,
            preferences: defaults
        )
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

    @Test("A decoder failure invalidates older route-retry authority")
    func playbackFailureRetriesByReloadingAfterRouteFailure() async {
        let setup = makeStereoCoordinator(route: builtIn)
        await setup.start()
        setup.native.loadError = PlaybackFailure(
            trackID: setup.track.track.id,
            message: "AirPlay unavailable"
        )
        setup.provider.emit(airPlay)
        await setup.coordinator.waitForAudioRouteTransitions()
        setup.provider.setCurrentRouteWithoutNotification(builtIn)

        let decoderFailure = PlaybackFailure(
            trackID: setup.track.track.id,
            message: "Decoder failed"
        )
        setup.pcm.emit(.failed(decoderFailure))
        #expect(setup.coordinator.state.failure == decoderFailure)
        #expect(setup.coordinator.currentBassLevel() == 0)
        let loadCount = setup.pcm.loadRequests.count
        let playCount = setup.pcm.playCount
        let verificationCount = setup.pcm.verifyStartCount
        setup.pcm.shouldSuspendNextLoad = true

        let retry = Task { @MainActor in
            await setup.coordinator.retryFailedCurrent()
        }
        await waitForSuspendedLoad(setup.pcm)
        setup.pcm.bassMeter.store(0.9)

        #expect(setup.coordinator.currentBassLevel() == 0)
        #expect(setup.pcm.playCount == playCount)
        setup.pcm.resumeNextLoad()
        #expect(await retry.value)

        #expect(setup.pcm.loadRequests.count == loadCount + 1)
        #expect(setup.pcm.verifyStartCount == verificationCount + 1)
        #expect(setup.pcm.playCount == playCount)
        #expect(setup.coordinator.state.failure == nil)
        #expect(setup.coordinator.state.transport == .playing)
    }

    @Test("A successful new item load invalidates older route failure authority")
    func newItemFailureRetriesByReloadingCurrentItem() async {
        let tracks = [
            playbackTestTrack(id: UUID(), title: "First"),
            playbackTestTrack(id: UUID(), title: "Second"),
        ]
        let provider = PlaybackTestAudioRouteProvider(route: builtIn)
        let pcm = PlaybackTestBackend(kind: .pcm)
        let native = PlaybackTestBackend(
            kind: .native,
            exposesRealtimeBass: true
        )
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [pcm, native],
            audioRouteProvider: provider
        )
        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: tracks.map(\.track.id)
            )
        )
        native.loadError = PlaybackFailure(
            trackID: tracks[0].track.id,
            message: "AirPlay unavailable"
        )
        provider.emit(airPlay)
        await coordinator.waitForAudioRouteTransitions()
        native.loadError = nil

        await coordinator.skipFailedTrack()
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)
        #expect(coordinator.state.activeBackend == .native)
        native.bassMeter.store(0.6)
        #expect(coordinator.currentBassLevel() == 0.6)

        let decoderFailure = PlaybackFailure(
            trackID: tracks[1].track.id,
            message: "Second decoder failed"
        )
        native.emit(.failed(decoderFailure))
        #expect(coordinator.state.failure == decoderFailure)
        #expect(coordinator.currentBassLevel() == 0)
        let loadCount = native.loadRequests.count
        let playCount = native.playCount
        let verificationCount = native.verifyStartCount
        native.shouldSuspendNextLoad = true

        let retry = Task { @MainActor in
            await coordinator.retryFailedCurrent()
        }
        await waitForSuspendedLoad(native)
        native.bassMeter.store(0.9)

        #expect(coordinator.currentBassLevel() == 0)
        #expect(native.playCount == playCount)
        native.resumeNextLoad()
        #expect(await retry.value)

        #expect(native.loadRequests.count == loadCount + 1)
        #expect(native.verifyStartCount == verificationCount + 1)
        #expect(native.playCount == playCount)
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)
        #expect(coordinator.state.failure == nil)
        #expect(coordinator.state.transport == .playing)
    }

    @Test("A missing required backend pauses and reports the route")
    func missingBackend() async {
        let track = playbackTestTrack(id: UUID(), title: "PCM Only")
        let provider = PlaybackTestAudioRouteProvider(route: builtIn)
        let pcm = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
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
        let provider = PlaybackTestAudioRouteProvider(route: builtIn)
        let pcm = PlaybackTestBackend(kind: .pcm)
        let native = PlaybackTestBackend(kind: .native)
        let coordinator = makePlaybackCoordinator(
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
        let provider = PlaybackTestAudioRouteProvider(route: builtIn)
        let coordinator = makePlaybackCoordinator(
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
        route: AudioRouteSnapshot,
        preferences: UserDefaults? = nil,
        bassEnvelopeLoader: @escaping PlaybackBassEnvelopeLoading =
            defaultPlaybackBassEnvelopeLoader
    ) -> RouteMonitoringSetup {
        let track = playbackTestTrack(id: UUID(), title: "Route Test")
        let provider = PlaybackTestAudioRouteProvider(route: route)
        let pcm = PlaybackTestBackend(kind: .pcm)
        let native = PlaybackTestBackend(kind: .native)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm, native],
            audioRouteProvider: provider,
            preferences: preferences,
            bassEnvelopeLoader: bassEnvelopeLoader
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
        _ backend: PlaybackTestBackend,
        count expectedCount: Int = 1
    ) async {
        for _ in 0 ..< 40
            where backend.suspendedLoadCount < expectedCount {
            await Task.yield()
        }
        #expect(backend.suspendedLoadCount == expectedCount)
    }
}

@MainActor
private struct RouteMonitoringSetup {
    let track: ResolvedPlaybackTrack
    let provider: PlaybackTestAudioRouteProvider
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
