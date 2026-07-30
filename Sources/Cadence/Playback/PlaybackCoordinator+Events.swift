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
            publishState()
        case let .failed(failure):
            failCurrent(with: failure)
            Task {
                await skipFailedCurrent()
            }
        case let .finished(trackID, successorStarted):
            guard state.currentTrack?.id == trackID else {
                return
            }
            Task {
                await handleFinishedItem(successorStarted: successorStarted)
            }
        case let .time(time):
            state.currentTime = min(max(time, 0), state.duration)
            publishState()
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
            Task { await seek(to: state.currentTime - interval) }
        case let .skipForward(interval):
            Task { await seek(to: state.currentTime + interval) }
        case .toggle:
            togglePlayback()
        }
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

    func publishState() {
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
}
