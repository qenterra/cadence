import Foundation

private struct PlaybackBackendTransition {
    let currentTrack: PlaybackTrack
    let currentID: UUID
    let previousKind: PlaybackBackendKind
    let previousBackend: any PlaybackBackend
    let requestedKind: PlaybackBackendKind
    let requestedBackend: any PlaybackBackend
    let wasPlaying: Bool
    let currentTime: TimeInterval
    let previousAudioPath: AudioPathSnapshot?
    let candidateRoute: AudioRouteSnapshot?
    let expectedRouteGeneration: Int?
    let expectedConfigurationGeneration: Int?
}

private enum PlaybackBackendTransitionFailurePolicy {
    case pauseAndReportRouteFailure
    case restorePreviousPath
}

private struct PlaybackBackendTransitionExpectation {
    let routeGeneration: Int?
    let configurationGeneration: Int?
}

extension PlaybackCoordinator {
    func transitionBackend(
        to requestedKind: PlaybackBackendKind,
        configurationGeneration: Int
    ) async -> Bool {
        await performBackendTransition(
            to: requestedKind,
            candidateRoute: nil,
            expectation: PlaybackBackendTransitionExpectation(
                routeGeneration: nil,
                configurationGeneration: configurationGeneration
            ),
            reloadCurrentBackend: false,
            failurePolicy: .restorePreviousPath
        )
    }

    func transitionForAudioRoute(
        to requestedKind: PlaybackBackendKind,
        route: AudioRouteSnapshot,
        generation: Int,
        reloadCurrentBackend: Bool
    ) async -> Bool {
        await performBackendTransition(
            to: requestedKind,
            candidateRoute: route,
            expectation: PlaybackBackendTransitionExpectation(
                routeGeneration: generation,
                configurationGeneration: nil
            ),
            reloadCurrentBackend: reloadCurrentBackend,
            failurePolicy: .pauseAndReportRouteFailure
        )
    }

    private func performBackendTransition(
        to requestedKind: PlaybackBackendKind,
        candidateRoute: AudioRouteSnapshot?,
        expectation: PlaybackBackendTransitionExpectation,
        reloadCurrentBackend: Bool,
        failurePolicy: PlaybackBackendTransitionFailurePolicy
    ) async -> Bool {
        guard
            let currentTrack = state.currentTrack,
            let currentID = state.queue?.currentTrackID,
            let previousKind = state.activeBackend,
            let previousBackend = backends[previousKind],
            let requestedBackend = backends[requestedKind]
        else {
            return false
        }
        guard requestedKind != previousKind || reloadCurrentBackend else {
            return true
        }

        let transition = PlaybackBackendTransition(
            currentTrack: currentTrack,
            currentID: currentID,
            previousKind: previousKind,
            previousBackend: previousBackend,
            requestedKind: requestedKind,
            requestedBackend: requestedBackend,
            wasPlaying: configurationTransitionWasPlaying ?? state.isPlaying,
            currentTime: presentationTime(),
            previousAudioPath: state.audioPath,
            candidateRoute: candidateRoute,
            expectedRouteGeneration: expectation.routeGeneration,
            expectedConfigurationGeneration: expectation.configurationGeneration
        )
        begin(transition)

        do {
            let prepared = try await prepare(transition)
            try await requestedBackend.load(prepared.request)
            guard routeTransitionIsCurrent(transition) else {
                requestedBackend.stop()
                return false
            }
            commit(transition, next: prepared.next)
            return true
        } catch {
            guard routeTransitionIsCurrent(transition) else {
                requestedBackend.stop()
                return false
            }
            handleFailure(
                transition,
                after: error,
                policy: failurePolicy
            )
            return false
        }
    }

    private func begin(_ transition: PlaybackBackendTransition) {
        if transition.expectedConfigurationGeneration != nil {
            configurationTransitionWasPlaying = transition.wasPlaying
        } else {
            transition.previousBackend.pause()
        }
        state.transport = .loading
        state.isBuffering = true
        publishState()
    }

    private func prepare(
        _ transition: PlaybackBackendTransition
    ) async throws -> (
        request: PlaybackBackendLoadRequest,
        next: ResolvedPlaybackTrack?
    ) {
        let ids = [transition.currentID, followingTrackID].compactMap(\.self)
        let resolved = try await resolver.resolve(trackIDs: ids)
        resolvedTracks.merge(
            resolved.map { ($0.track.id, $0) },
            uniquingKeysWith: { _, new in new }
        )
        guard let current = resolvedTracks[transition.currentID] else {
            throw PlaybackFailure(
                trackID: transition.currentID,
                message: "The current managed audio file is unavailable."
            )
        }
        let gain = replayGain(for: current.track)
        let next = compatibleNext(
            for: transition.requestedKind,
            route: transition.candidateRoute,
            replayGain: gain
        )
        let request = PlaybackBackendLoadRequest(
            current: current,
            next: repeatMode == .one ? nil : next,
            startTime: transition.currentTime,
            autoplay: transition.wasPlaying,
            volume: volume,
            replayGainDecibels: gain
        )
        return (request, next)
    }

    private func compatibleNext(
        for backend: PlaybackBackendKind,
        route: AudioRouteSnapshot?,
        replayGain: Double?
    ) -> ResolvedPlaybackTrack? {
        followingTrackID
            .flatMap { resolvedTracks[$0] }
            .flatMap { candidate in
                routeBackend(
                    for: candidate.track,
                    route: route
                ) == backend
                    && self.replayGain(for: candidate.track) == replayGain
                    ? candidate
                    : nil
            }
    }

    private func commit(
        _ transition: PlaybackBackendTransition,
        next: ResolvedPlaybackTrack?
    ) {
        if transition.previousKind != transition.requestedKind {
            transition.previousBackend.stop()
        }
        loadGeneration += 1
        if let candidateRoute = transition.candidateRoute {
            outputRoute = candidateRoute
            routeFailureIsActive = false
        }
        state.currentTrack = transition.currentTrack
        state.currentTime = transition.currentTime
        state.duration = transition.currentTrack.duration
        state.activeBackend = transition.requestedKind
        state.transport = transition.wasPlaying ? .playing : .paused
        state.isBuffering = false
        state.failure = nil
        state.audioPath = audioPath(
            current: transition.currentTrack,
            backend: transition.requestedKind,
            next: next,
            route: transition.candidateRoute
        )
        if transition.expectedConfigurationGeneration != nil {
            configurationTransitionWasPlaying = nil
        }
        publishState()
    }

    private func handleFailure(
        _ transition: PlaybackBackendTransition,
        after error: Error,
        policy: PlaybackBackendTransitionFailurePolicy
    ) {
        transition.requestedBackend.stop()
        if transition.expectedConfigurationGeneration != nil {
            configurationTransitionWasPlaying = nil
        }
        switch policy {
        case .pauseAndReportRouteFailure:
            transition.previousBackend.pause()
            routeFailureIsActive = true
            state.activeBackend = transition.previousKind
            state.transport = .paused
            state.isBuffering = false
            state.failure = PlaybackFailure(
                trackID: transition.currentID,
                message: "The new audio output could not be activated: "
                    + error.localizedDescription
            )
            state.audioPath = transition.previousAudioPath
        case .restorePreviousPath:
            state.activeBackend = transition.previousKind
            state.transport = transition.wasPlaying ? .playing : .paused
            state.isBuffering = false
            state.failure = PlaybackFailure(
                trackID: transition.currentID,
                message: "The audio path could not be changed: "
                    + error.localizedDescription
            )
            state.audioPath = audioPath(
                current: transition.currentTrack,
                backend: transition.previousKind,
                next: nil
            )
        }
        publishState()
    }

    private func routeTransitionIsCurrent(
        _ transition: PlaybackBackendTransition
    ) -> Bool {
        let routeIsCurrent = transition.expectedRouteGeneration.map {
            $0 == routeGeneration
        } ?? true
        let configurationIsCurrent = transition.expectedConfigurationGeneration.map {
            $0 == audioConfigurationGeneration
        } ?? true
        return routeIsCurrent && configurationIsCurrent
    }
}
