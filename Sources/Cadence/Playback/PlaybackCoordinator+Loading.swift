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

        let (generation, intent) = beginLoading(
            currentID: currentID,
            autoplay: autoplay
        )

        do {
            return try await performLoad(
                currentID: currentID,
                startTime: startTime,
                autoplay: autoplay,
                generation: generation,
                expectedIntent: intent
            )
        } catch {
            guard generation == loadGeneration,
                  playbackIntent.currentItemID == currentID,
                  playbackIntent.transport != .failed,
                  playbackIntent.transport != .idle
            else {
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
        generation: Int,
        expectedIntent: PlaybackIntentAuthority
    ) async throws -> Bool {
        let prepared = try await prepareLoad(currentID: currentID)
        guard generation == loadGeneration,
              playbackIntent.currentItemID == currentID,
              playbackIntent.generation >= expectedIntent.generation
        else {
            return false
        }
        backends.values
            .filter { $0.kind != prepared.backend.kind }
            .forEach { $0.stop() }
        stage(prepared, startTime: startTime)
        let request = PlaybackBackendLoadRequest(
            current: prepared.current,
            next: repeatMode == .one ? nil : prepared.next,
            startTime: startTime,
            autoplay: autoplay,
            volume: volume,
            normalizationGain: normalizationGain(
                for: prepared.current.track
            )
        )
        try await loadVerified(
            prepared.backend,
            request: request,
            generation: generation
        )
        guard generation == loadGeneration,
              playbackIntent.currentItemID == currentID
        else {
            prepared.backend.stop()
            return false
        }
        let acceptedTransport = playbackIntent.transport
        guard acceptedTransport != .failed,
              acceptedTransport != .idle
        else {
            prepared.backend.stop()
            return false
        }
        if acceptedTransport.shouldAutoplay != autoplay {
            if acceptedTransport.shouldAutoplay {
                prepared.backend.play()
            } else {
                prepared.backend.pause()
            }
        }
        commit(
            prepared,
            startTime: startTime,
            transport: acceptedTransport
        )
        if acceptedTransport == .playing {
            activateBassSource(
                for: prepared.current,
                backend: prepared.backend
            )
        }
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

    private func beginLoading(
        currentID: UUID,
        autoplay: Bool
    ) -> (generation: Int, intent: PlaybackIntentAuthority) {
        invalidateBassState()
        invalidateRouteFailureAuthority()
        loadGeneration += 1
        let intent = advancePlaybackIntent(
            currentItemID: currentID,
            transport: autoplay ? .playing : .paused
        )
        outputRoute = audioRouteProvider.currentRoute()
        state.transport = .loading
        state.isBuffering = true
        state.failure = nil
        publishState()
        return (loadGeneration, intent)
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
        transport: PlaybackIntentTransport
    ) {
        state.currentTrack = prepared.current.track
        state.currentTime = startTime
        state.duration = prepared.current.track.duration
        state.activeBackend = prepared.backend.kind
        state.transport = transport.state
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

    func prepareFollowingTrack(
        expectedIntent: PlaybackIntentAuthority? = nil
    ) async {
        let intent = expectedIntent ?? playbackIntent
        let expectedLoadGeneration = loadGeneration
        let expectedRouteGeneration = routeGeneration
        guard followingPreparationIsCurrent(
            intent: intent,
            loadGeneration: expectedLoadGeneration,
            routeGeneration: expectedRouteGeneration
        ), let activeBackend, repeatMode != .one else {
            return
        }
        let backendKind = activeBackend.kind
        do {
            let nextID = followingTrackID
            if let nextID, resolvedTracks[nextID] == nil {
                let tracks = try await resolver.resolve(trackIDs: [nextID])
                guard followingPreparationIsCurrent(
                    intent: intent,
                    loadGeneration: expectedLoadGeneration,
                    routeGeneration: expectedRouteGeneration,
                    backend: backendKind
                ) else {
                    return
                }
                resolvedTracks.merge(
                    tracks.map { ($0.track.id, $0) },
                    uniquingKeysWith: { _, new in new }
                )
            }
            let next = nextID.flatMap { resolvedTracks[$0] }
            let hasMatchingBackend = next.map {
                routeBackend(for: $0.track) == activeBackend.kind
            } ?? false
            guard followingPreparationIsCurrent(
                intent: intent,
                loadGeneration: expectedLoadGeneration,
                routeGeneration: expectedRouteGeneration,
                backend: backendKind
            ) else {
                return
            }
            guard hasMatchingBackend else {
                try await activeBackend.prepareNext(nil)
                guard followingPreparationIsCurrent(
                    intent: intent,
                    loadGeneration: expectedLoadGeneration,
                    routeGeneration: expectedRouteGeneration,
                    backend: backendKind
                ) else {
                    return
                }
                refreshAudioPath(next: nil)
                return
            }
            try await activeBackend.prepareNext(next)
            guard followingPreparationIsCurrent(
                intent: intent,
                loadGeneration: expectedLoadGeneration,
                routeGeneration: expectedRouteGeneration,
                backend: backendKind
            ) else {
                return
            }
            refreshAudioPath(next: next)
        } catch {
            if followingPreparationIsCurrent(
                intent: intent,
                loadGeneration: expectedLoadGeneration,
                routeGeneration: expectedRouteGeneration,
                backend: backendKind
            ) {
                refreshAudioPath(next: nil)
            }
        }
    }

    private func followingPreparationIsCurrent(
        intent: PlaybackIntentAuthority,
        loadGeneration: Int,
        routeGeneration: Int,
        backend: PlaybackBackendKind? = nil
    ) -> Bool {
        intent == playbackIntent
            && intent.currentItemID == state.currentTrack?.id
            && intent.currentItemID == state.queue?.currentTrackID
            && loadGeneration == self.loadGeneration
            && routeGeneration == self.routeGeneration
            && (backend == nil || backend == state.activeBackend)
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
