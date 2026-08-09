import Foundation

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
            Task {
                await handleFinishedItem(successorStarted: successorStarted)
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
        reason: MoveReason
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
        _ = await loadCurrent(startTime: 0, autoplay: true)
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

    func failCurrent(with error: Error) {
        let failure = error as? PlaybackFailure
            ?? PlaybackFailure(
                trackID: state.currentTrack?.id,
                message: error.localizedDescription
            )
        if let trackID = failure.trackID ?? state.currentTrack?.id {
            failedTrackIDs.insert(trackID)
        }
        state.failure = failure
        state.transport = .failed
        state.isBuffering = false
        publishState()
    }

    func pauseForSilentStartFailure(
        _ failure: PlaybackFailure
    ) {
        if let trackID = failure.trackID ?? state.currentTrack?.id {
            failedTrackIDs.insert(trackID)
        }
        state.failure = failure
        state.transport = .paused
        state.isBuffering = false
        publishState()
    }

    private func handleFinishedItem(
        successorStarted: UUID?
    ) async {
        if repeatMode == .one {
            _ = await loadCurrent(startTime: 0, autoplay: true)
            return
        }

        if let successorStarted,
           var queue = state.queue,
           queue.move(to: successorStarted),
           let successor = resolvedTracks[successorStarted] {
            state.queue = queue
            state.currentTrack = successor.track
            state.currentTime = 0
            state.duration = successor.track.duration
            state.transport = .playing
            state.failure = nil
            publishState()
            await prepareFollowingTrack()
            return
        }

        await move(by: 1, reason: .completion)
    }

    func skipFailedCurrent() async {
        guard let queue = state.queue,
              failedTrackIDs.count < queue.orderedTrackIDs.count
        else {
            let failure = state.failure
            stop(resetQueue: false)
            state.failure = failure
            state.transport = .failed
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
        if routeFailureIsActive {
            retryAudioRouteAndPlay()
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
