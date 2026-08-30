@testable import Cadence
import Foundation
import Testing

@MainActor
struct PlaybackCustomizationTests {
    @Test("Previous can skip directly to the prior track")
    func alwaysPreviousBehavior() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            PreviousTrackBehavior.alwaysPrevious.rawValue,
            forKey: CadencePreferences.Keys.previousTrackBehavior
        )
        let first = playbackTestTrack(id: UUID(), title: "First")
        let second = playbackTestTrack(id: UUID(), title: "Second")
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [first, second]),
            backends: [backend],
            preferences: defaults
        )
        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [first.track.id, second.track.id],
                startingAt: second.track.id
            )
        )
        backend.emit(.time(42))

        await coordinator.previous()

        #expect(coordinator.state.currentTrack?.id == first.track.id)
        #expect(backend.seekTimes.isEmpty)
    }

    @Test("Seek commands use the configured interval")
    func configuredSeekInterval() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            SeekInterval.seconds30.rawValue,
            forKey: CadencePreferences.Keys.seekInterval
        )
        let track = playbackTestTrack(id: UUID(), title: "Seek")
        let backend = PlaybackTestBackend(kind: .pcm)
        let media = PlaybackTestSystemMediaSession()
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [backend],
            systemMediaSession: media,
            preferences: defaults
        )
        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [track.track.id]
            )
        )
        backend.emit(.time(10))

        media.send(.skipForward(15))
        await Task.yield()

        #expect(media.preferredSkipInterval == 30)
        #expect(backend.seekTimes == [40])
    }

    @Test("Track ReplayGain becomes a safe linear backend gain")
    func replayGainPolicy() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            VolumeNormalizationMode.track.rawValue,
            forKey: CadencePreferences.Keys.volumeNormalization
        )
        let track = playbackTestTrack(
            id: UUID(),
            title: "Quiet Master",
            replayGainTrackGain: -6
        )
        let backend = PlaybackTestBackend(kind: .pcm)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [backend],
            preferences: defaults
        )

        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [track.track.id]
            )
        )

        let gain = try #require(backend.loadRequests.first?.normalizationGain)
        #expect(abs(gain - 0.501_187) < 0.000_01)
        #expect(
            PlaybackNormalization.gain(
                mode: .track,
                trackGainDecibels: 6,
                trackPeak: 1
            ) == 1
        )
    }

    @Test("Crossfade preference reaches the renderer and the coordinator adopts once")
    func configuredCrossfadeAdoptsSuccessorOnce() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            CrossfadeDuration.seconds4.rawValue,
            forKey: CadencePreferences.Keys.crossfadeDuration
        )
        let first = playbackTestTrack(
            id: UUID(),
            title: "First",
            duration: 100,
            replayGainTrackGain: -6
        )
        let second = playbackTestTrack(
            id: UUID(),
            title: "Second",
            duration: 80,
            replayGainTrackGain: -3
        )
        let primary = PlaybackTestBackend(kind: .pcm)
        let secondary = PlaybackTestBackend(kind: .pcm)
        let backend = CrossfadePlaybackBackend(
            kind: .pcm,
            primary: primary,
            secondary: secondary
        )
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [first, second]),
            backends: [backend],
            preferences: defaults
        )

        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [first.track.id, second.track.id]
            )
        )
        await waitUntil { secondary.loadRequests.count == 1 }
        #expect(primary.loadRequests.first?.next == nil)
        #expect(secondary.loadRequests.first?.current.track.id == second.track.id)

        primary.emit(.timeline(.init(mediaTime: 96.1, hostUptime: 1, rate: 1)))
        await waitUntil {
            coordinator.state.currentTrack?.id == second.track.id
        }
        primary.emit(.finished(trackID: first.track.id, successorStarted: nil))
        await Task.yield()

        #expect(coordinator.state.currentTrack?.id == second.track.id)
        #expect(coordinator.state.queue?.currentIndex == 1)
        #expect(coordinator.state.duration == second.track.duration)
        #expect(coordinator.state.audioPath?.codec == second.track.codec)
    }

    @Test("A managed queue restores paused at the saved item and position")
    func queueRestoration() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        CadencePreferences.registerDefaults(in: defaults)
        let first = playbackTestTrack(id: UUID(), title: "First")
        let second = playbackTestTrack(id: UUID(), title: "Second")
        let tracks = [first, second]
        let initialBackend = PlaybackTestBackend(kind: .pcm)
        let initial = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [initialBackend],
            preferences: defaults
        )
        #expect(
            await initial.startQueue(
                source: .album(UUID()),
                trackIDs: tracks.map(\.track.id),
                startingAt: second.track.id
            )
        )
        initial.repeatMode = .all
        initialBackend.emit(.time(37))
        initial.pause()

        let restoredBackend = PlaybackTestBackend(kind: .pcm)
        let restored = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: tracks),
            backends: [restoredBackend],
            preferences: defaults
        )
        #expect(
            await restored.restorePersistedSession(
                validTrackIDs: Set(tracks.map(\.track.id))
            )
        )

        #expect(restored.state.currentTrack?.id == second.track.id)
        #expect(restored.state.transport == .paused)
        #expect(restored.repeatMode == .all)
        #expect(restoredBackend.loadRequests.first?.startTime == 37)
        #expect(restoredBackend.loadRequests.first?.autoplay == false)
    }

    @Test("Playback resumes after a failed output route recovers when enabled")
    func automaticRouteRecovery() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        CadencePreferences.registerDefaults(in: defaults)
        let builtIn = AudioRouteSnapshot(name: "Mac", transport: .builtIn)
        let airPlay = AudioRouteSnapshot(name: "Room", transport: .airPlay)
        let wired = AudioRouteSnapshot(name: "DAC", transport: .wired)
        let track = playbackTestTrack(id: UUID(), title: "Route")
        let pcm = PlaybackTestBackend(kind: .pcm)
        let native = PlaybackTestBackend(kind: .native)
        let provider = PlaybackTestAudioRouteProvider(route: builtIn)
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [track]),
            backends: [pcm, native],
            audioRouteProvider: provider,
            preferences: defaults
        )
        #expect(
            await coordinator.startQueue(
                source: .adHoc,
                trackIDs: [track.track.id]
            )
        )
        native.loadError = PlaybackFailure(
            trackID: track.track.id,
            message: "Output unavailable"
        )

        provider.emit(airPlay)
        await coordinator.waitForAudioRouteTransitions()
        #expect(coordinator.state.transport == .paused)
        #expect(coordinator.state.failure != nil)

        native.loadError = nil
        provider.emit(wired)
        await coordinator.waitForAudioRouteTransitions()

        #expect(coordinator.state.transport == .playing)
        #expect(coordinator.state.failure == nil)
        #expect(pcm.playCount == 1)
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "PlaybackCustomizationTests-\(UUID().uuidString)"
        return try (#require(UserDefaults(suiteName: suite)), suite)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 100 where !condition() {
            await Task.yield()
        }
    }
}
