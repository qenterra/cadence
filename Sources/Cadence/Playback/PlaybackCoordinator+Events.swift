import Foundation

private struct PlaybackCompletionExpectation {
    let backend: PlaybackBackendKind
    let currentItemID: UUID
    let intent: PlaybackIntentAuthority
    let loadGeneration: Int
    let routeGeneration: Int
}

extension PlaybackCoordinator {
    enum MoveReason {
        case completion
        case manual
    }

    func receive(
        _ event: PlaybackBackendEvent,
        from backend: PlaybackBackendKind
    ) {
        guard backend == state.activeBackend else {
            return
        }
        switch event {
        case let .duration(duration):
            state.duration = max(duration, 0)
            publishState(reanchorPresentationClock: false)
        case let .failed(failure):
            failCurrent(with: failure)
        case let .finished(trackID, successorStarted):
            guard state.currentTrack?.id == trackID else {
                return
            }
            if let successorStarted,
               reconcileStartedSuccessor(
                   predecessorID: trackID,
                   successorID: successorStarted
               ) {
                return
            }
            let expectation = PlaybackCompletionExpectation(
                backend: backend,
                currentItemID: trackID,
                intent: playbackIntent,
                loadGeneration: loadGeneration,
                routeGeneration: routeGeneration
            )
            Task { @MainActor [weak self] in
                await self?.handleFinishedItem(expectation: expectation)
            }
        case let .timeline(sample):
            presentationClock.update(sample)
            if shouldPublishTimeline(sample) {
                state.currentTime = min(
                    max(sample.mediaTime, 0),
                    state.duration
                )
                lastTimelinePublication = sample
                publishState(reanchorPresentationClock: false)
            }
        case let .time(time):
            state.currentTime = min(max(time, 0), state.duration)
            presentationClock.update(
                PlaybackTimelineSample(
                    mediaTime: state.currentTime,
                    hostUptime: ProcessInfo.processInfo.systemUptime,
                    rate: 0
                )
            )
            publishState(reanchorPresentationClock: false)
        }
    }

    func perform(_ command: SystemMediaCommand) {
        switch command {
        case let .changePosition(time):
            Task { await seek(to: time) }
        case .next:
            Task { await next() }
        case .pause:
            pause()
        case .play:
            play()
        case .previous:
            Task { await previous() }
        case let .skipBackward(interval):
            Task { await seek(to: presentationTime() - interval) }
        case let .skipForward(interval):
            Task { await seek(to: presentationTime() + interval) }
        case .toggle:
            togglePlayback()
        }
    }

    private func shouldPublishTimeline(
        _ sample: PlaybackTimelineSample
    ) -> Bool {
        guard let previous = lastTimelinePublication else {
            return true
        }
        return sample.rate != previous.rate
            || sample.hostUptime - previous.hostUptime >= 1
    }

    func move(
        by offset: Int,
        reason: MoveReason,
        autoplay: Bool = true
    ) async {
        guard var queue = state.queue else {
            return
        }
        let wrapping = repeatMode == .all || reason == .manual
        guard queue.move(
            by: offset,
            wrapping: wrapping,
            excluding: failedTrackIDs
        ) != nil else {
            stop(resetQueue: false)
            return
        }
        if reason == .manual, state.isPlaying {
            await activeBackend?.setPresentationGain(
                0,
                duration: .milliseconds(80)
            )
        }
        state.queue = queue
        _ = await loadCurrent(startTime: 0, autoplay: autoplay)
    }

    func publishState(
        reanchorPresentationClock: Bool = true
    ) {
        let indicator = PlaybackIndicatorState(
            currentTrackID: state.currentTrack?.id,
            isPlaying: state.isPlaying
        )
        if indicator != playbackIndicator {
            playbackIndicator = indicator
        }
        if reanchorPresentationClock {
            presentationClock.update(
                PlaybackTimelineSample(
                    mediaTime: state.currentTime,
                    hostUptime: ProcessInfo.processInfo.systemUptime,
                    rate: state.isPlaying ? 1 : 0
                )
            )
        }
        systemMediaSession.update(state: state)
    }

    func refreshManagedArtwork(
        _ artworkIDsByTrackID: [UUID: UUID?]
    ) {
        guard
            !artworkIDsByTrackID.isEmpty,
            state.queue?.source != .externalFiles
        else {
            return
        }

        for (trackID, artworkID) in artworkIDsByTrackID {
            guard
                let resolved = resolvedTracks[trackID],
                resolved.track.artworkID != artworkID
            else {
                continue
            }
            resolvedTracks[trackID] = ResolvedPlaybackTrack(
                track: resolved.track.replacingArtworkID(artworkID),
                mediaURL: resolved.mediaURL
            )
        }

        guard
            let current = state.currentTrack,
            let artworkID = artworkIDsByTrackID[current.id],
            current.artworkID != artworkID
        else {
            return
        }
        state.currentTrack = current.replacingArtworkID(artworkID)
        publishState(reanchorPresentationClock: false)
    }

    func failCurrent(with error: Error) {
        invalidateBassState()
        invalidateRouteFailureAuthority()
        let failure = error as? PlaybackFailure
            ?? PlaybackFailure(
                trackID: state.currentTrack?.id,
                message: error.localizedDescription
            )
        if let trackID = failure.trackID ?? state.currentTrack?.id {
            failedTrackIDs.insert(trackID)
        }
        advancePlaybackIntent(
            currentItemID: state.currentTrack?.id,
            transport: .failed
        )
        state.failure = failure
        state.transport = .failed
        state.isBuffering = false
        publishState()
    }

    func pauseForSilentStartFailure(
        _ failure: PlaybackFailure
    ) {
        invalidateBassState()
        invalidateRouteFailureAuthority()
        if let trackID = failure.trackID ?? state.currentTrack?.id {
            failedTrackIDs.insert(trackID)
        }
        advancePlaybackIntent(
            currentItemID: state.currentTrack?.id,
            transport: .paused
        )
        state.failure = failure
        state.transport = .paused
        state.isBuffering = false
        publishState()
    }

    private func handleFinishedItem(
        expectation: PlaybackCompletionExpectation
    ) async {
        guard completionIsCurrent(expectation),
              expectation.intent.transport == .playing
        else {
            return
        }
        let autoplay = expectation.intent.transport.shouldAutoplay
        if repeatMode == .one {
            _ = await loadCurrent(startTime: 0, autoplay: autoplay)
            return
        }
        await move(
            by: 1,
            reason: .completion,
            autoplay: autoplay
        )
    }

    private func reconcileStartedSuccessor(
        predecessorID: UUID,
        successorID: UUID
    ) -> Bool {
        guard playbackIntent.currentItemID == predecessorID,
              state.queue?.currentTrackID == predecessorID,
              var queue = state.queue,
              queue.move(to: successorID),
              let successor = resolvedTracks[successorID]
        else {
            return false
        }

        let intendedTransport = playbackIntent.transport
        clearVisibleRouteFailureAuthority(
            currentItemID: predecessorID
        )
        state.queue = queue
        state.currentTrack = successor.track
        state.currentTime = 0
        state.duration = successor.track.duration
        state.transport = intendedTransport.state
        state.isBuffering = false
        if intendedTransport == .playing {
            state.failure = nil
        }
        let adoptedIntent = advancePlaybackIntent(
            currentItemID: successorID,
            transport: intendedTransport
        )
        if intendedTransport == .playing {
            activateBassSourceForCurrentTrack()
        } else {
            invalidateBassState()
            activeBackend?.pause()
        }
        publishState()
        Task { @MainActor [weak self] in
            await self?.prepareFollowingTrack(expectedIntent: adoptedIntent)
        }
        return true
    }

    private func completionIsCurrent(
        _ expectation: PlaybackCompletionExpectation
    ) -> Bool {
        expectation.backend == state.activeBackend
            && expectation.currentItemID == state.currentTrack?.id
            && expectation.currentItemID == state.queue?.currentTrackID
            && expectation.intent == playbackIntent
            && expectation.loadGeneration == loadGeneration
            && expectation.routeGeneration == routeGeneration
    }

    func skipFailedCurrent() async {
        guard let queue = state.queue,
              failedTrackIDs.count < queue.orderedTrackIDs.count
        else {
            let failure = state.failure
            stop(resetQueue: false)
            state.failure = failure
            state.transport = .failed
            advancePlaybackIntent(
                currentItemID: state.queue?.currentTrackID,
                transport: .failed
            )
            publishState()
            return
        }
        await move(by: 1, reason: .completion)
    }

    @discardableResult
    func retryFailedCurrent() async -> Bool {
        guard
            state.failure != nil,
            let currentID = state.queue?.currentTrackID
        else {
            return false
        }
        if retryableRouteFailureAuthority != nil {
            let intent = advancePlaybackIntent(
                currentItemID: currentID,
                transport: .playing
            )
            retryAudioRouteAndPlay(expectedIntent: intent)
            return true
        }
        let startTime = state.currentTrack?.id == currentID
            ? state.currentTime
            : 0
        failedTrackIDs.remove(currentID)
        resolvedTracks.removeValue(forKey: currentID)
        return await loadCurrent(
            startTime: startTime,
            autoplay: true
        )
    }

    func skipFailedTrack() async {
        guard state.failure != nil else {
            return
        }
        await skipFailedCurrent()
    }
}
