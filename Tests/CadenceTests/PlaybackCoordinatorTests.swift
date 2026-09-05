// This integration suite intentionally keeps the coordinator's state-machine coverage together.
// swiftlint:disable file_length

@testable import Cadence
import Foundation
import Testing

@MainActor
struct PlaybackCoordinatorTests {
    @Test("Artwork metadata refreshes without resolving or restarting audio")
    func artworkMetadataRefreshDoesNotRestartAudio() async {
        let first = playbackTestTrack(
            id: UUID(),
            title: "Current",
            artworkID: UUID()
        )
        let second = playbackTestTrack(
            id: UUID(),
            title: "Next",
            artworkID: UUID()
        )
        let replacementArtworkID = UUID()
        let nextReplacementArtworkID = UUID()
        let resolver = PlaybackTestResolver(tracks: [first, second])
        let backend = PlaybackTestBackend(kind: .pcm)
        let media = PlaybackTestSystemMediaSession()
        let coordinator = makePlaybackCoordinator(
            resolver: resolver,
            backends: [backend],
            systemMediaSession: media
        )
        #expect(
            await coordinator.startQueue(
                source: .album(UUID()),
                trackIDs: [first.track.id, second.track.id]
            )
        )
        backend.emit(.time(41))
        let stateBefore = coordinator.state
        let firstMediaURL = coordinator.resolvedTracks[first.track.id]?.mediaURL
        let secondMediaURL = coordinator.resolvedTracks[second.track.id]?.mediaURL
        let resolverRequests = resolver.requests
        let loadRequestCount = backend.loadRequests.count
        let preparedTrackCount = backend.preparedTracks.count
        let playCount = backend.playCount
        let pauseCount = backend.pauseCount
        let stopCount = backend.stopCount
        let loadGeneration = coordinator.loadGeneration
        let routeGeneration = coordinator.routeGeneration

        coordinator.refreshManagedArtwork([
            first.track.id: replacementArtworkID,
            second.track.id: nextReplacementArtworkID,
        ])

        #expect(coordinator.state.currentTrack?.artworkID == replacementArtworkID)
        #expect(
            coordinator.resolvedTracks[first.track.id]?.track.artworkID
                == replacementArtworkID
        )
        #expect(
            coordinator.resolvedTracks[second.track.id]?.track.artworkID
                == nextReplacementArtworkID
        )
        #expect(coordinator.resolvedTracks[first.track.id]?.mediaURL == firstMediaURL)
        #expect(coordinator.resolvedTracks[second.track.id]?.mediaURL == secondMediaURL)
        #expect(coordinator.state.transport == stateBefore.transport)
        #expect(coordinator.state.queue == stateBefore.queue)
        #expect(coordinator.state.currentTime == stateBefore.currentTime)
        #expect(coordinator.state.duration == stateBefore.duration)
        #expect(coordinator.state.activeBackend == stateBefore.activeBackend)
        #expect(coordinator.state.audioPath == stateBefore.audioPath)
        #expect(resolver.requests == resolverRequests)
        #expect(backend.loadRequests.count == loadRequestCount)
        #expect(backend.preparedTracks.count == preparedTrackCount)
        #expect(backend.playCount == playCount)
        #expect(backend.pauseCount == pauseCount)
        #expect(backend.stopCount == stopCount)
        #expect(coordinator.loadGeneration == loadGeneration)
        #expect(coordinator.routeGeneration == routeGeneration)
        #expect(media.states.last?.currentTrack?.artworkID == replacementArtworkID)
    }

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
        let coordinator = makePlaybackCoordinator(
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

    @Test("Coordinator alerts once when each new track starts playing")
    func trackChangeNotifications() async throws {
        let suiteName = "PlaybackNotificationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            true,
            forKey: CadenceNotificationPreferences.trackChangesKey
        )
        let notificationCenter = CadenceNotificationCenterSpy()
        let notificationController = CadenceNotificationController(
            center: notificationCenter,
            defaults: defaults
        )
        let tracks = [
            playbackTestTrack(id: UUID(), title: "One"),
            playbackTestTrack(id: UUID(), title: "Two"),
        ]
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [PlaybackTestBackend(kind: .pcm)],
            notificationController: notificationController
        )

        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: tracks.map(\.track.id)
            )
        )
        coordinator.pause()
        coordinator.play()
        await coordinator.next()

        #expect(notificationCenter.notifications.map(\.title) == ["One", "Two"])
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
        let coordinator = makePlaybackCoordinator(
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
        let coordinator = makePlaybackCoordinator(
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
        let pcm = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: resolver,
            backends: [pcm]
        )

        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: tracks.map(\.track.id)
        )

        #expect(coordinator.state.queue?.currentTrackID == tracks[0].track.id)
        #expect(coordinator.state.failure != nil)
        #expect(coordinator.state.transport == .failed)
        #expect(pcm.loadRequests.isEmpty)

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
        let coordinator = makePlaybackCoordinator(
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
        let coordinator = makePlaybackCoordinator(
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
        let coordinator = makePlaybackCoordinator(
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

    @Test("The selected route never substitutes another playback backend")
    func missingSelectedBackendFailsExplicitly() async {
        let track = playbackTestTrack(id: UUID(), title: "PCM Required")
        let native = PlaybackTestBackend(kind: .native)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [native]
        )

        #expect(
            await !(coordinator.startQueue(
                source: .adHoc,
                trackIDs: [track.track.id]
            ))
        )
        #expect(native.loadRequests.isEmpty)
        #expect(coordinator.state.transport == .failed)
        #expect(
            coordinator.state.failure?.message.contains(
                "No compatible playback backend"
            ) == true
        )
    }

    @Test("A silent PCM start is rescheduled once before Playing")
    func silentPCMStartRetriesOnce() async {
        let track = playbackTestTrack(id: UUID(), title: "Retry")
        let backend = PlaybackTestBackend(kind: .pcm)
        backend.startObservations = [
            .failed(.renderDidNotAdvance),
            .started,
        ]
        let coordinator = makePlaybackCoordinator(
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
        let coordinator = makePlaybackCoordinator(
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

extension PlaybackCoordinatorTests {
    @Test("Bass provider is live only while PCM playback is accepted")
    func bassProviderTransportLifecycle() async {
        let track = playbackTestTrack(id: UUID(), title: "Bass")
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [backend]
        )

        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [track.track.id]
            )
        )
        backend.bassMeter.store(0.7)
        #expect(coordinator.currentBassLevel() == 0.7)

        let pauseGeneration = coordinator.bassGeneration
        let pauseResetCount = backend.resetBassCount
        coordinator.pause()
        #expect(coordinator.currentBassLevel() == 0)
        #expect(coordinator.bassGeneration == pauseGeneration + 1)
        #expect(backend.resetBassCount == pauseResetCount + 1)

        let resumeResetCount = backend.resetBassCount
        coordinator.play()
        #expect(
            backend.resetBassCountAtLastPlay
                == resumeResetCount + 1
        )
        #expect(coordinator.currentBassLevel() == 0)
        backend.bassMeter.store(0.4)
        #expect(coordinator.currentBassLevel() == 0.4)

        backend.shouldSuspendNextSeek = true
        let seekGeneration = coordinator.bassGeneration
        let stalePublicationEpoch = backend.bassMeter.publicationEpoch()
        let seekTask = Task {
            await coordinator.seek(to: 20)
        }
        for _ in 0 ..< 20 where backend.suspendedSeekCount == 0 {
            await Task.yield()
        }
        #expect(backend.suspendedSeekCount == 1)
        backend.bassMeter.store(0.9)
        #expect(coordinator.currentBassLevel() == 0)
        backend.resumeNextSeek()
        await seekTask.value
        #expect(coordinator.currentBassLevel() == 0)
        #expect(coordinator.bassGeneration > seekGeneration)

        #expect(
            !backend.bassMeter.store(
                0.9,
                ifPublicationEpoch: stalePublicationEpoch
            )
        )
        #expect(coordinator.currentBassLevel() == 0)

        let activePublicationEpoch = backend.bassMeter.publicationEpoch()
        #expect(
            backend.bassMeter.store(
                0.5,
                ifPublicationEpoch: activePublicationEpoch
            )
        )
        #expect(coordinator.currentBassLevel() == 0.5)
        let stopGeneration = coordinator.bassGeneration
        coordinator.stop()
        #expect(coordinator.currentBassLevel() == 0)
        #expect(coordinator.bassGeneration == stopGeneration + 1)
    }

    @Test("Shutdown invalidates accepted bass state")
    func bassShutdownLifecycle() async {
        let track = playbackTestTrack(id: UUID(), title: "Shutdown")
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [backend]
        )

        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [track.track.id]
            )
        )
        backend.bassMeter.store(0.65)
        let generation = coordinator.bassGeneration
        let resetCount = backend.resetBassCount

        coordinator.shutdown()

        #expect(coordinator.currentBassLevel() == 0)
        #expect(coordinator.bassGeneration == generation + 1)
        #expect(backend.resetBassCount == resetCount + 1)
    }

    @Test("Failed load and gapless successor never inherit PCM bass")
    func bassLoadFailureAndGaplessSuccessor() async {
        let tracks = [
            playbackTestTrack(id: UUID(), title: "First"),
            playbackTestTrack(id: UUID(), title: "Second"),
        ]
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [backend]
        )
        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: tracks.map(\.track.id)
            )
        )

        backend.bassMeter.store(0.8)
        let successorGeneration = coordinator.bassGeneration
        backend.emit(
            .finished(
                trackID: tracks[0].track.id,
                successorStarted: tracks[1].track.id
            )
        )
        await Task.yield()
        await Task.yield()
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)
        #expect(coordinator.currentBassLevel() == 0)
        #expect(coordinator.bassGeneration > successorGeneration)

        backend.bassMeter.store(0.6)
        backend.loadError = PlaybackFailure(
            trackID: tracks[0].track.id,
            message: "Rejected"
        )
        await coordinator.previous()
        #expect(coordinator.state.transport == .failed)
        #expect(coordinator.currentBassLevel() == 0)
    }

    @Test("A successor reported after Pause preserves paused intent")
    func lateGaplessSuccessorAfterPause() async {
        let tracks = [
            playbackTestTrack(id: UUID(), title: "First"),
            playbackTestTrack(id: UUID(), title: "Second"),
        ]
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [backend]
        )
        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: tracks.map(\.track.id)
            )
        )
        let playCount = backend.playCount

        coordinator.pause()
        backend.emit(
            .finished(
                trackID: tracks[0].track.id,
                successorStarted: tracks[1].track.id
            )
        )
        await Task.yield()
        await Task.yield()
        backend.bassMeter.store(0.9)

        #expect(coordinator.state.queue?.currentTrackID == tracks[1].track.id)
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)
        #expect(coordinator.state.transport == .paused)
        #expect(coordinator.currentBassLevel() == 0)
        #expect(backend.playCount == playCount)
    }

    @Test("Pause wins after a successor completion was already accepted")
    func pauseAfterAcceptedGaplessSuccessor() async {
        let tracks = [
            playbackTestTrack(id: UUID(), title: "First"),
            playbackTestTrack(id: UUID(), title: "Second"),
        ]
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [backend]
        )
        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: tracks.map(\.track.id)
            )
        )
        let playCount = backend.playCount

        backend.emit(
            .finished(
                trackID: tracks[0].track.id,
                successorStarted: tracks[1].track.id
            )
        )
        coordinator.pause()
        await Task.yield()
        await Task.yield()
        backend.bassMeter.store(0.85)

        #expect(coordinator.state.queue?.currentTrackID == tracks[1].track.id)
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)
        #expect(coordinator.state.transport == .paused)
        #expect(coordinator.currentBassLevel() == 0)
        #expect(backend.playCount == playCount)
    }

    @Test("A late successor cannot erase a newer playback failure")
    func lateGaplessSuccessorAfterFailure() async {
        let tracks = [
            playbackTestTrack(id: UUID(), title: "First"),
            playbackTestTrack(id: UUID(), title: "Second"),
        ]
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [backend]
        )
        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: tracks.map(\.track.id)
            )
        )
        let failure = PlaybackFailure(
            trackID: tracks[0].track.id,
            message: "Decoder failed"
        )

        coordinator.failCurrent(with: failure)
        backend.emit(
            .finished(
                trackID: tracks[0].track.id,
                successorStarted: tracks[1].track.id
            )
        )
        await Task.yield()
        await Task.yield()
        backend.bassMeter.store(0.8)

        #expect(coordinator.state.queue?.currentTrackID == tracks[1].track.id)
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)
        #expect(coordinator.state.transport == .failed)
        #expect(coordinator.state.failure == failure)
        #expect(coordinator.currentBassLevel() == 0)
    }

    @Test("Stale Native envelope workers cannot cross a track generation")
    func staleNativeEnvelopeAfterTrackSwitch() async {
        let tracks = [
            playbackTestTrack(id: UUID(), title: "First"),
            playbackTestTrack(id: UUID(), title: "Second"),
        ]
        let loader = PlaybackTestBassEnvelopeLoader()
        let native = PlaybackTestBackend(
            kind: .native,
            exposesRealtimeBass: false
        )
        let route = PlaybackTestAudioRouteProvider(
            route: AudioRouteSnapshot(name: "AirPlay", transport: .airPlay)
        )
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [native],
            audioRouteProvider: route,
            bassEnvelopeLoader: { url in await loader.load(url) }
        )

        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [tracks[0].track.id]
            )
        )
        let receivedFirst = await waitForBassEnvelopeRequests(
            1,
            loader: loader
        )
        #expect(receivedFirst)
        guard receivedFirst else {
            return
        }

        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [tracks[1].track.id]
            )
        )
        let receivedSecond = await waitForBassEnvelopeRequests(
            2,
            loader: loader
        )
        #expect(receivedSecond)
        guard receivedSecond else {
            return
        }

        await loader.resumeNext(
            with: playbackTestBassEnvelope(level: 0.9)
        )
        await Task.yield()
        await Task.yield()
        #expect(coordinator.state.currentTrack?.id == tracks[1].track.id)
        #expect(coordinator.currentBassLevel() == 0)

        await loader.resumeNext(
            with: playbackTestBassEnvelope(level: 0.4)
        )
        let acceptedSecond = await waitForBassLevel(
            0.4,
            coordinator: coordinator
        )
        #expect(acceptedSecond)
    }

    @Test("Accepted Native bass envelope is reused across pause and resume")
    func nativeBassEnvelopeCacheReusedOnResume() async {
        let track = playbackTestTrack(id: UUID(), title: "Cached")
        let loader = PlaybackTestBassEnvelopeLoader()
        let native = PlaybackTestBackend(
            kind: .native,
            exposesRealtimeBass: false
        )
        let route = PlaybackTestAudioRouteProvider(
            route: AudioRouteSnapshot(name: "AirPlay", transport: .airPlay)
        )
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [native],
            audioRouteProvider: route,
            bassEnvelopeLoader: { url in await loader.load(url) }
        )

        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [track.track.id]
            )
        )
        let requested = await waitForBassEnvelopeRequests(1, loader: loader)
        #expect(requested)
        guard requested else {
            return
        }
        await loader.resumeNext(
            with: playbackTestBassEnvelope(level: 0.6)
        )
        #expect(
            await waitForBassLevel(0.6, coordinator: coordinator)
        )

        coordinator.pause()
        coordinator.play()
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        #expect(await loader.requestCount() == 1)
        #expect(coordinator.currentBassLevel() == 0.6)
    }

    @Test("Native bass envelope cache is bounded least-recently-used state")
    func nativeBassEnvelopeCacheIsBounded() {
        let first = playbackTestTrack(id: UUID(), title: "First")
        let second = playbackTestTrack(id: UUID(), title: "Second")
        let third = playbackTestTrack(id: UUID(), title: "Third")
        let firstKey = PlaybackBassMediaIdentity(resolved: first)
        let secondKey = PlaybackBassMediaIdentity(resolved: second)
        let thirdKey = PlaybackBassMediaIdentity(resolved: third)
        let firstEnvelope = playbackTestBassEnvelope(level: 0.2)
        let secondEnvelope = playbackTestBassEnvelope(level: 0.4)
        let thirdEnvelope = playbackTestBassEnvelope(level: 0.6)
        var cache = PlaybackBassEnvelopeCache(capacity: 2)

        cache.insert(firstEnvelope, for: firstKey)
        cache.insert(secondEnvelope, for: secondKey)
        #expect(cache.value(for: firstKey) == firstEnvelope)
        cache.insert(thirdEnvelope, for: thirdKey)

        #expect(cache.count == 2)
        #expect(cache.value(for: firstKey) == firstEnvelope)
        #expect(cache.value(for: secondKey) == nil)
        #expect(cache.value(for: thirdKey) == thirdEnvelope)
    }

    @Test("Stopping rejects a suspended Native envelope")
    func staleNativeEnvelopeAfterStop() async {
        let track = playbackTestTrack(id: UUID(), title: "Stop")
        let loader = PlaybackTestBassEnvelopeLoader()
        let native = PlaybackTestBackend(
            kind: .native,
            exposesRealtimeBass: false
        )
        let route = PlaybackTestAudioRouteProvider(
            route: AudioRouteSnapshot(name: "AirPlay", transport: .airPlay)
        )
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [native],
            audioRouteProvider: route,
            bassEnvelopeLoader: { url in await loader.load(url) }
        )

        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [track.track.id]
            )
        )
        let received = await waitForBassEnvelopeRequests(1, loader: loader)
        #expect(received)
        guard received else {
            return
        }
        coordinator.stop()
        await loader.resumeNext(
            with: playbackTestBassEnvelope(level: 1)
        )
        await Task.yield()
        await Task.yield()

        #expect(coordinator.state.currentTrack == nil)
        #expect(coordinator.currentBassLevel() == 0)
        #expect(coordinator.bassEnvelope == nil)
    }
}

extension PlaybackCoordinatorTests {
    @Test(
        "A late nil completion preserves Pause or failure in every queue mode",
        arguments: NilCompletionTerminalCase.all
    )
    func lateNilCompletionPreservesNewestIntent(
        _ testCase: NilCompletionTerminalCase
    ) async {
        let setup = await makeNilCompletionSetup(testCase.queueScenario)
        setup.backend.bassMeter.store(0.8)
        let expectedFailure = apply(
            testCase.terminalIntent,
            to: setup
        )
        let loadCount = setup.backend.loadRequests.count
        let playCount = setup.backend.playCount
        let stopCount = setup.backend.stopCount

        setup.backend.emit(
            .finished(
                trackID: setup.first.track.id,
                successorStarted: nil
            )
        )
        await settleNilCompletion()

        #expect(setup.backend.loadRequests.count == loadCount)
        #expect(setup.backend.playCount == playCount)
        #expect(setup.backend.stopCount == stopCount)
        #expect(setup.coordinator.state.currentTrack?.id == setup.first.track.id)
        #expect(setup.coordinator.state.queue?.currentTrackID == setup.first.track.id)
        #expect(
            setup.coordinator.state.transport
                == testCase.terminalIntent.transport
        )
        #expect(setup.coordinator.state.failure == expectedFailure)
        #expect(setup.coordinator.currentBassLevel() == 0)
    }

    @Test(
        "Pause or failure wins after a nil completion was accepted",
        arguments: NilCompletionTerminalCase.all
    )
    func newestIntentRejectsAcceptedNilCompletion(
        _ testCase: NilCompletionTerminalCase
    ) async {
        let setup = await makeNilCompletionSetup(testCase.queueScenario)
        setup.backend.bassMeter.store(0.75)
        let loadCount = setup.backend.loadRequests.count

        setup.backend.emit(
            .finished(
                trackID: setup.first.track.id,
                successorStarted: nil
            )
        )
        let expectedFailure = apply(
            testCase.terminalIntent,
            to: setup
        )
        let playCount = setup.backend.playCount
        let stopCount = setup.backend.stopCount
        await settleNilCompletion()

        #expect(setup.backend.loadRequests.count == loadCount)
        #expect(setup.backend.playCount == playCount)
        #expect(setup.backend.stopCount == stopCount)
        #expect(setup.coordinator.state.currentTrack?.id == setup.first.track.id)
        #expect(setup.coordinator.state.queue?.currentTrackID == setup.first.track.id)
        #expect(
            setup.coordinator.state.transport
                == testCase.terminalIntent.transport
        )
        #expect(setup.coordinator.state.failure == expectedFailure)
        #expect(setup.coordinator.currentBassLevel() == 0)
    }

    @Test(
        "A current Playing nil completion advances, repeats, or stops",
        arguments: NilCompletionQueueScenario.allCases
    )
    func playingNilCompletionKeepsAutomaticProgression(
        _ queueScenario: NilCompletionQueueScenario
    ) async {
        let setup = await makeNilCompletionSetup(queueScenario)
        setup.backend.bassMeter.store(0.7)
        let loadCount = setup.backend.loadRequests.count
        let stopCount = setup.backend.stopCount

        setup.backend.emit(
            .finished(
                trackID: setup.first.track.id,
                successorStarted: nil
            )
        )
        await settleNilCompletion()

        #expect(setup.coordinator.currentBassLevel() == 0)
        switch queueScenario {
        case .advance:
            #expect(setup.backend.loadRequests.count == loadCount + 1)
            #expect(setup.backend.loadRequests.last?.autoplay == true)
            #expect(setup.coordinator.state.currentTrack?.id == setup.second?.track.id)
            #expect(setup.coordinator.state.queue?.currentTrackID == setup.second?.track.id)
            #expect(setup.coordinator.state.transport == .playing)
        case .repeatOne:
            #expect(setup.backend.loadRequests.count == loadCount + 1)
            #expect(setup.backend.loadRequests.last?.autoplay == true)
            #expect(setup.coordinator.state.currentTrack?.id == setup.first.track.id)
            #expect(setup.coordinator.state.queue?.currentTrackID == setup.first.track.id)
            #expect(setup.coordinator.state.transport == .playing)
        case .queueEnd:
            #expect(setup.backend.loadRequests.count == loadCount)
            #expect(setup.backend.stopCount > stopCount)
            #expect(setup.coordinator.state.currentTrack == nil)
            #expect(setup.coordinator.state.queue?.currentTrackID == setup.first.track.id)
            #expect(setup.coordinator.state.transport == .idle)
        }
    }

    private func makeNilCompletionSetup(
        _ queueScenario: NilCompletionQueueScenario
    ) async -> NilCompletionSetup {
        let first = playbackTestTrack(id: UUID(), title: "First")
        let second = queueScenario == .queueEnd
            ? nil
            : playbackTestTrack(id: UUID(), title: "Second")
        let tracks = [first] + [second].compactMap(\.self)
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [backend]
        )
        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: tracks.map(\.track.id)
            )
        )
        if queueScenario == .repeatOne {
            coordinator.repeatMode = .one
        }
        return NilCompletionSetup(
            first: first,
            second: second,
            backend: backend,
            coordinator: coordinator
        )
    }

    private func apply(
        _ terminalIntent: NilCompletionTerminalIntent,
        to setup: NilCompletionSetup
    ) -> PlaybackFailure? {
        switch terminalIntent {
        case .paused:
            setup.coordinator.pause()
            return nil
        case .failed:
            let failure = PlaybackFailure(
                trackID: setup.first.track.id,
                message: "Decoder failed after completion"
            )
            setup.coordinator.failCurrent(with: failure)
            return failure
        }
    }

    private func settleNilCompletion() async {
        for _ in 0 ..< 6 {
            await Task.yield()
        }
    }
}

enum NilCompletionQueueScenario: CaseIterable, Sendable {
    case advance
    case repeatOne
    case queueEnd
}

enum NilCompletionTerminalIntent: CaseIterable, Sendable {
    case paused
    case failed

    var transport: PlaybackTransportState {
        switch self {
        case .paused:
            .paused
        case .failed:
            .failed
        }
    }
}

struct NilCompletionTerminalCase: Sendable {
    let queueScenario: NilCompletionQueueScenario
    let terminalIntent: NilCompletionTerminalIntent

    static let all = NilCompletionQueueScenario.allCases.flatMap { scenario in
        NilCompletionTerminalIntent.allCases.map { terminalIntent in
            NilCompletionTerminalCase(
                queueScenario: scenario,
                terminalIntent: terminalIntent
            )
        }
    }
}

@MainActor
private struct NilCompletionSetup {
    let first: ResolvedPlaybackTrack
    let second: ResolvedPlaybackTrack?
    let backend: PlaybackTestBackend
    let coordinator: PlaybackCoordinator
}
