import Foundation

private struct PreparedPlaybackLoad {
    let current: ResolvedPlaybackTrack
    let backend: any PlaybackBackend
    let next: ResolvedPlaybackTrack?
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
            return try await performLoad(
                currentID: currentID,
                startTime: startTime,
                autoplay: autoplay,
                generation: generation
            )
        } catch {
            guard generation == loadGeneration else {
                return false
            }
            if let failure = error as? PlaybackFailure,
               failure.kind == .silentStart {
                pauseForSilentStartFailure(failure)
            } else {
                failCurrent(with: error)
            }
            return false
        }
    }

    private func performLoad(
        currentID: UUID,
        startTime: TimeInterval,
        autoplay: Bool,
        generation: Int
    ) async throws -> Bool {
        let prepared = try await prepareLoad(currentID: currentID)
        guard generation == loadGeneration else {
            return false
        }
        backends.values
            .filter { $0.kind != prepared.backend.kind }
            .forEach { $0.stop() }
        stage(prepared, startTime: startTime)
        if prepared.backend.bassLevelProvider == nil {
            beginBassEnvelopeAnalysis(
                for: prepared.current,
                generation: generation
            )
        } else {
            cancelBassEnvelopeAnalysis()
        }
        let request = PlaybackBackendLoadRequest(
            current: prepared.current,
            next: repeatMode == .one ? nil : prepared.next,
            startTime: startTime,
            autoplay: autoplay,
            volume: volume
        )
        try await loadVerified(
            prepared.backend,
            request: request,
            generation: generation
        )
        guard generation == loadGeneration else {
            prepared.backend.stop()
            return false
        }
        commit(prepared, startTime: startTime, autoplay: autoplay)
        return true
    }

    private func loadVerified(
        _ backend: any PlaybackBackend,
        request: PlaybackBackendLoadRequest,
        generation: Int
    ) async throws {
        let attemptCount = request.autoplay && backend.kind == .pcm ? 2 : 1
        for attempt in 0 ..< attemptCount {
            try await backend.load(request)
            guard generation == loadGeneration else {
                throw CancellationError()
            }
            guard request.autoplay else {
                return
            }
            let observation = await backend.verifyStart(
                timeout: .milliseconds(350)
            )
            guard generation == loadGeneration else {
                throw CancellationError()
            }
            if observation == .started {
                return
            }
            backend.stop()
            if attempt == attemptCount - 1 {
                throw PlaybackFailure.silentStart(
                    trackID: request.current.track.id
                )
            }
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
        guard let backend = backends[kind] else {
            throw PlaybackFailure(
                trackID: currentID,
                message: "No compatible playback backend is available."
            )
        }
        let next = nextResolvedTrack(
            for: backend.kind,
            after: currentID
        )
        return PreparedPlaybackLoad(
            current: current,
            backend: backend,
            next: next
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

    private func stage(
        _ prepared: PreparedPlaybackLoad,
        startTime: TimeInterval
    ) {
        state.currentTrack = prepared.current.track
        state.currentTime = startTime
        state.duration = prepared.current.track.duration
        state.activeBackend = prepared.backend.kind
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
            guard hasMatchingBackend else {
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
                route: route ?? outputRoute
            )
        )
    }

    private func nextResolvedTrack(
        for backend: PlaybackBackendKind,
        after _: UUID
    ) -> ResolvedPlaybackTrack? {
        guard
            let followingTrackID,
            let next = resolvedTracks[followingTrackID],
            routeBackend(for: next.track) == backend
        else {
            return nil
        }
        return next
    }
}
