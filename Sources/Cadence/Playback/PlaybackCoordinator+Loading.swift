import Foundation

private struct PreparedPlaybackLoad {
    let current: ResolvedPlaybackTrack
    let backend: any PlaybackBackend
    let next: ResolvedPlaybackTrack?
    let replayGain: Double?
}

extension PlaybackCoordinator {
    @discardableResult
    func loadCurrent(
        startTime: TimeInterval,
        autoplay: Bool
    ) async -> Bool {
        await waitForAudioRouteTransitions()
        guard let currentID = state.queue?.currentTrackID else {
            stop()
            return false
        }

        let generation = beginLoading()

        do {
            let prepared = try await prepareLoad(currentID: currentID)
            guard generation == loadGeneration else {
                return false
            }
            backends.values
                .filter { $0.kind != prepared.backend.kind }
                .forEach { $0.stop() }
            try await prepared.backend.load(
                PlaybackBackendLoadRequest(
                    current: prepared.current,
                    next: repeatMode == .one ? nil : prepared.next,
                    startTime: startTime,
                    autoplay: autoplay,
                    volume: volume,
                    replayGainDecibels: prepared.replayGain
                )
            )
            guard generation == loadGeneration else {
                prepared.backend.stop()
                return false
            }
            commit(
                prepared,
                startTime: startTime,
                autoplay: autoplay
            )
            return true
        } catch {
            guard generation == loadGeneration else {
                return false
            }
            failCurrent(with: error)
            await skipFailedCurrent()
            return false
        }
    }

    private func beginLoading() -> Int {
        loadGeneration += 1
        outputRoute = audioRouteProvider.currentRoute()
        state.transport = .loading
        state.isBuffering = true
        state.failure = nil
        publishState()
        return loadGeneration
    }

    private func prepareLoad(
        currentID: UUID
    ) async throws -> PreparedPlaybackLoad {
        let ids = [currentID, followingTrackID].compactMap(\.self)
        let resolved = try await resolver.resolve(trackIDs: ids)
        resolvedTracks.merge(
            resolved.map { ($0.track.id, $0) },
            uniquingKeysWith: { _, new in new }
        )
        guard let current = resolvedTracks[currentID] else {
            throw PlaybackFailure(
                trackID: currentID,
                message: "The managed audio file is unavailable."
            )
        }
        let kind = routeBackend(for: current.track)
        guard let backend = backends[kind] ?? fallbackBackend else {
            throw PlaybackFailure(
                trackID: currentID,
                message: "No compatible playback backend is available."
            )
        }
        let gain = replayGain(for: current.track)
        let next = nextResolvedTrack(
            for: backend.kind,
            after: currentID,
            matchingReplayGain: gain
        )
        return PreparedPlaybackLoad(
            current: current,
            backend: backend,
            next: next,
            replayGain: gain
        )
    }

    private func commit(
        _ prepared: PreparedPlaybackLoad,
        startTime: TimeInterval,
        autoplay: Bool
    ) {
        state.currentTrack = prepared.current.track
        state.currentTime = startTime
        state.duration = prepared.current.track.duration
        state.activeBackend = prepared.backend.kind
        state.transport = autoplay ? .playing : .paused
        state.isBuffering = false
        state.audioPath = audioPath(
            current: prepared.current.track,
            backend: prepared.backend.kind,
            next: prepared.next
        )
        publishState()
    }

    func prepareFollowingTrack() async {
        guard let activeBackend, repeatMode != .one else {
            return
        }
        do {
            let nextID = followingTrackID
            if let nextID, resolvedTracks[nextID] == nil {
                let tracks = try await resolver.resolve(trackIDs: [nextID])
                resolvedTracks.merge(
                    tracks.map { ($0.track.id, $0) },
                    uniquingKeysWith: { _, new in new }
                )
            }
            let next = nextID.flatMap { resolvedTracks[$0] }
            let hasMatchingBackend = next.map {
                routeBackend(for: $0.track) == activeBackend.kind
            } ?? false
            let hasMatchingGain = next.map {
                replayGain(for: $0.track)
                    == state.currentTrack.flatMap(replayGain)
            } ?? false
            guard hasMatchingBackend, hasMatchingGain else {
                try await activeBackend.prepareNext(nil)
                refreshAudioPath(next: nil)
                return
            }
            try await activeBackend.prepareNext(next)
            refreshAudioPath(next: next)
        } catch {
            refreshAudioPath(next: nil)
        }
    }

    var followingTrackID: UUID? {
        guard let queue = state.queue else {
            return nil
        }
        let nextIndex = queue.currentIndex + 1
        if queue.orderedTrackIDs.indices.contains(nextIndex) {
            return queue.orderedTrackIDs[nextIndex]
        }
        return repeatMode == .all ? queue.orderedTrackIDs.first : nil
    }

    func routeBackend(
        for track: PlaybackTrack,
        route: AudioRouteSnapshot? = nil
    ) -> PlaybackBackendKind {
        PlaybackRoutingPolicy.backend(
            for: PlaybackRoutingRequest(
                track: track,
                profile: qualityProfile,
                route: route ?? outputRoute,
                stereoSpatializationEnabled: stereoSpatializationEnabled
            )
        )
    }

    private var fallbackBackend: (any PlaybackBackend)? {
        backends[.native] ?? backends[.pcm]
    }

    private func nextResolvedTrack(
        for backend: PlaybackBackendKind,
        after _: UUID,
        matchingReplayGain: Double?
    ) -> ResolvedPlaybackTrack? {
        guard
            let followingTrackID,
            let next = resolvedTracks[followingTrackID],
            routeBackend(for: next.track) == backend,
            replayGain(for: next.track) == matchingReplayGain
        else {
            return nil
        }
        return next
    }

    func replayGain(for track: PlaybackTrack) -> Double? {
        guard qualityProfile == .adaptive,
              let gain = track.replayGainTrackGain
        else {
            return nil
        }
        if let peak = track.replayGainTrackPeak, peak > 0 {
            let maximumGain = -20 * log10(peak)
            return min(gain, maximumGain)
        }
        return gain
    }
}
