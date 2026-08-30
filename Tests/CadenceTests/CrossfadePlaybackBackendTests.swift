@testable import Cadence
import Foundation
import Testing

@MainActor
struct CrossfadePlaybackBackendTests {
    @Test("Crossfade preloads the successor and adopts it before the outgoing track ends")
    func startsPreparedSuccessor() async throws {
        let first = playbackTestTrack(
            id: UUID(),
            title: "First",
            duration: 100
        )
        let second = playbackTestTrack(
            id: UUID(),
            title: "Second",
            duration: 80
        )
        let primary = PlaybackTestBackend(kind: .pcm)
        let secondary = PlaybackTestBackend(kind: .pcm)
        let backend = CrossfadePlaybackBackend(
            kind: .pcm,
            primary: primary,
            secondary: secondary
        )
        var startedSuccessor: (UUID, UUID)?
        backend.onEvent = { event in
            if case let .finished(trackID, successorID) = event,
               let successorID {
                startedSuccessor = (trackID, successorID)
            }
        }

        try await loadCrossfade(
            backend,
            current: first,
            next: second,
            normalizationGain: 0.8,
            nextNormalizationGain: 0.6
        )
        await waitUntil { secondary.loadRequests.count == 1 }

        #expect(primary.loadRequests.first?.next == nil)
        #expect(secondary.loadRequests.first?.current.track.id == second.track.id)
        #expect(secondary.loadRequests.first?.autoplay == false)
        #expect(secondary.loadRequests.first?.normalizationGain == 0.6)

        primary.emit(.timeline(.init(mediaTime: 96.1, hostUptime: 1, rate: 1)))
        await waitUntil {
            startedSuccessor != nil && !primary.presentationGains.isEmpty
        }

        #expect(startedSuccessor?.0 == first.track.id)
        #expect(startedSuccessor?.1 == second.track.id)
        #expect(secondary.fadeInDurations == [.seconds(4)])
        #expect(primary.presentationGains.last?.gain == 0)
        #expect(primary.presentationGains.last?.duration == .seconds(4))
        expectTrebleTransition(primary: primary, secondary: secondary)
    }

    @Test("Disabled crossfade preserves the backend's native successor preparation")
    func disabledUsesNativePreparation() async throws {
        let first = playbackTestTrack(id: UUID(), title: "First")
        let second = playbackTestTrack(id: UUID(), title: "Second")
        let primary = PlaybackTestBackend(kind: .pcm)
        let secondary = PlaybackTestBackend(kind: .pcm)
        let backend = CrossfadePlaybackBackend(
            kind: .pcm,
            primary: primary,
            secondary: secondary
        )

        try await backend.load(
            PlaybackBackendLoadRequest(
                current: first,
                next: second,
                startTime: 0,
                autoplay: true,
                volume: 0.7,
                crossfadeDuration: 0
            )
        )

        #expect(primary.loadRequests.first?.next?.track.id == second.track.id)
        #expect(secondary.loadRequests.isEmpty)
    }

    @Test("Short tracks clamp overlap and repeated timeline events adopt once")
    func clampsShortTracksAndAdoptsOnce() async throws {
        let first = playbackTestTrack(
            id: UUID(),
            title: "Short First",
            duration: 10
        )
        let second = playbackTestTrack(
            id: UUID(),
            title: "Short Second",
            duration: 6
        )
        let primary = PlaybackTestBackend(kind: .pcm)
        let secondary = PlaybackTestBackend(kind: .pcm)
        let backend = CrossfadePlaybackBackend(
            kind: .pcm,
            primary: primary,
            secondary: secondary
        )
        var adoptionCount = 0
        backend.onEvent = { event in
            if case .finished(_, .some) = event {
                adoptionCount += 1
            }
        }
        try await backend.load(
            PlaybackBackendLoadRequest(
                current: first,
                next: second,
                startTime: 0,
                autoplay: true,
                volume: 0.7,
                crossfadeDuration: 12
            )
        )
        await waitUntil { secondary.loadRequests.count == 1 }

        primary.emit(.timeline(.init(mediaTime: 6.9, hostUptime: 1, rate: 1)))
        #expect(adoptionCount == 0)
        primary.emit(.timeline(.init(mediaTime: 7.1, hostUptime: 2, rate: 1)))
        await waitUntil { !primary.presentationGains.isEmpty }
        primary.emit(.timeline(.init(mediaTime: 9, hostUptime: 3, rate: 1)))

        #expect(adoptionCount == 1)
        #expect(secondary.fadeInDurations == [.seconds(3)])
        #expect(primary.presentationGains.last?.duration == .seconds(3))
    }

    @Test("A failed successor preload falls back to ordinary completion")
    func failedPreloadFallsBack() async throws {
        let first = playbackTestTrack(id: UUID(), title: "First")
        let second = playbackTestTrack(id: UUID(), title: "Second")
        let primary = PlaybackTestBackend(kind: .pcm)
        let secondary = PlaybackTestBackend(kind: .pcm)
        secondary.loadError = PlaybackFailure(
            trackID: second.track.id,
            message: "Preload failed"
        )
        let backend = CrossfadePlaybackBackend(
            kind: .pcm,
            primary: primary,
            secondary: secondary
        )
        var completions: [(UUID, UUID?)] = []
        backend.onEvent = { event in
            if case let .finished(trackID, successorID) = event {
                completions.append((trackID, successorID))
            }
        }
        try await backend.load(
            PlaybackBackendLoadRequest(
                current: first,
                next: second,
                startTime: 0,
                autoplay: true,
                volume: 0.7,
                crossfadeDuration: 4
            )
        )
        await waitUntil { secondary.loadAttemptCount == 1 }

        primary.emit(.timeline(.init(mediaTime: 119, hostUptime: 1, rate: 1)))
        primary.emit(.finished(trackID: first.track.id, successorStarted: nil))

        #expect(completions.count == 1)
        #expect(completions.first?.0 == first.track.id)
        #expect(completions.first?.1 == nil)
        #expect(secondary.fadeInDurations.isEmpty)
    }

    @Test("Pause, seek, and stop retire an in-flight overlap safely")
    func transportCommandsRetireOverlap() async throws {
        let first = playbackTestTrack(id: UUID(), title: "First")
        let second = playbackTestTrack(id: UUID(), title: "Second")
        let primary = PlaybackTestBackend(kind: .pcm)
        let secondary = PlaybackTestBackend(kind: .pcm)
        primary.shouldSuspendNextPresentationGain = true
        let backend = CrossfadePlaybackBackend(
            kind: .pcm,
            primary: primary,
            secondary: secondary
        )
        try await backend.load(
            PlaybackBackendLoadRequest(
                current: first,
                next: second,
                startTime: 0,
                autoplay: true,
                volume: 0.7,
                crossfadeDuration: 4
            )
        )
        await waitUntil { secondary.loadRequests.count == 1 }
        primary.emit(.timeline(.init(mediaTime: 117, hostUptime: 1, rate: 1)))
        await waitUntil { primary.suspendedPresentationGainCount == 1 }

        backend.pause()
        try await backend.seek(to: 12)
        backend.stop()
        primary.resumeNextPresentationGain()
        await Task.yield()

        #expect(secondary.pauseCount == 1)
        #expect(secondary.seekTimes == [12])
        #expect(primary.stopCount >= 2)
        #expect(secondary.stopCount >= 2)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 100 where !condition() {
            await Task.yield()
        }
    }

    private func loadCrossfade(
        _ backend: CrossfadePlaybackBackend,
        current: ResolvedPlaybackTrack,
        next: ResolvedPlaybackTrack,
        normalizationGain: Float,
        nextNormalizationGain: Float
    ) async throws {
        try await backend.load(
            PlaybackBackendLoadRequest(
                current: current,
                next: next,
                startTime: 0,
                autoplay: true,
                volume: 0.7,
                normalizationGain: normalizationGain,
                nextNormalizationGain: nextNormalizationGain,
                crossfadeDuration: 4
            )
        )
    }
}

@MainActor
private func expectTrebleTransition(
    primary: PlaybackTestBackend,
    secondary: PlaybackTestBackend
) {
    #expect(secondary.crossfadeTrebleOpenness.first?.openness == 0)
    #expect(secondary.crossfadeTrebleOpenness.first?.duration == .zero)
    #expect(primary.crossfadeTrebleOpenness.last?.openness == 0)
    #expect(primary.crossfadeTrebleOpenness.last?.duration == .seconds(4))
    #expect(secondary.crossfadeTrebleOpenness.last?.openness == 1)
    #expect(secondary.crossfadeTrebleOpenness.last?.duration == .seconds(4))
}
