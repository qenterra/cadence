import Foundation

enum PlaybackBackendTransitionResult {
    case committed
    case failed
    case superseded
}

private struct PlaybackBackendTransition {
    let currentTrack: PlaybackTrack
    let currentID: UUID
    let previousKind: PlaybackBackendKind
    let previousBackend: any PlaybackBackend
    let requestedKind: PlaybackBackendKind
    let requestedBackend: any PlaybackBackend
    let expectedIntent: PlaybackIntentAuthority
    let currentTime: TimeInterval
    let previousAudioPath: AudioPathSnapshot?
    let candidateRoute: AudioRouteSnapshot?
    let expectedRouteGeneration: Int?
}

private struct PlaybackBackendTransitionExpectation {
    let routeGeneration: Int?
    let intent: PlaybackIntentAuthority
}

extension PlaybackCoordinator {
    func transitionForAudioRoute(
        to requestedKind: PlaybackBackendKind,
        route: AudioRouteSnapshot,
        generation: Int,
        reloadCurrentBackend: Bool
    ) async -> PlaybackBackendTransitionResult {
        await performBackendTransition(
            to: requestedKind,
            candidateRoute: route,
            expectation: PlaybackBackendTransitionExpectation(
                routeGeneration: generation,
                intent: playbackIntent
            ),
            reloadCurrentBackend: reloadCurrentBackend
        )
    }

    private func performBackendTransition(
        to requestedKind: PlaybackBackendKind,
        candidateRoute: AudioRouteSnapshot?,
        expectation: PlaybackBackendTransitionExpectation,
        reloadCurrentBackend: Bool
    ) async -> PlaybackBackendTransitionResult {
        guard
            let currentTrack = state.currentTrack,
            let currentID = state.queue?.currentTrackID,
            currentID == expectation.intent.currentItemID,
            let previousKind = state.activeBackend,
            let previousBackend = backends[previousKind],
            let requestedBackend = backends[requestedKind]
        else {
            return .failed
        }
        guard requestedKind != previousKind || reloadCurrentBackend else {
            return .committed
        }

        let transition = PlaybackBackendTransition(
            currentTrack: currentTrack,
            currentID: currentID,
            previousKind: previousKind,
            previousBackend: previousBackend,
            requestedKind: requestedKind,
            requestedBackend: requestedBackend,
            expectedIntent: expectation.intent,
            currentTime: presentationTime(),
            previousAudioPath: state.audioPath,
            candidateRoute: candidateRoute,
            expectedRouteGeneration: expectation.routeGeneration
        )
        begin(transition)

        do {
            let prepared = try await prepare(transition)
            guard routeTransitionIsCurrent(transition) else {
                rejectSuperseded(transition)
                return .superseded
            }
            try await requestedBackend.load(prepared.request)
            guard routeTransitionIsCurrent(transition) else {
                rejectSuperseded(transition)
                return .superseded
            }
            commit(transition, next: prepared.next)
            return .committed
        } catch {
            guard routeTransitionIsCurrent(transition) else {
                rejectSuperseded(transition)
                return .superseded
            }
            handleFailure(transition, after: error)
            return .failed
        }
    }

    private func begin(_ transition: PlaybackBackendTransition) {
        invalidateBassState()
        transition.previousBackend.pause()
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
        let next = compatibleNext(
            for: transition.requestedKind,
            route: transition.candidateRoute
        )
        let request = PlaybackBackendLoadRequest(
            current: current,
            next: repeatMode == .one ? nil : next,
            startTime: transition.currentTime,
            autoplay: false,
            volume: volume,
            normalizationGain: normalizationGain(
                for: current.track
            )
        )
        return (request, next)
    }

    private func compatibleNext(
        for backend: PlaybackBackendKind,
        route: AudioRouteSnapshot?
    ) -> ResolvedPlaybackTrack? {
        followingTrackID
            .flatMap { resolvedTracks[$0] }
            .flatMap { candidate in
                routeBackend(
                    for: candidate.track,
                    route: route
                ) == backend
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
        }
        clearVisibleRouteFailureAuthority(
            currentItemID: transition.currentID
        )
        finishRouteRecovery()
        state.currentTrack = transition.currentTrack
        state.currentTime = transition.currentTime
        state.duration = transition.currentTrack.duration
        state.activeBackend = transition.requestedKind
        let intendedTransport = transition.expectedIntent.transport
        state.transport = intendedTransport.state
        state.isBuffering = false
        if intendedTransport != .failed {
            state.failure = nil
        }
        state.audioPath = audioPath(
            current: transition.currentTrack,
            backend: transition.requestedKind,
            next: next,
            route: transition.candidateRoute
        )
        if intendedTransport == .playing {
            transition.requestedBackend.play()
            activateBassSourceForCurrentTrack()
        } else {
            invalidateBassState()
        }
        publishState()
    }

    private func handleFailure(
        _ transition: PlaybackBackendTransition,
        after error: Error
    ) {
        transition.requestedBackend.stop()
        transition.previousBackend.pause()
        routeRecoveryShouldResume =
            transition.expectedIntent.transport == .playing
        advancePlaybackIntent(
            currentItemID: transition.currentID,
            transport: .paused
        )
        state.activeBackend = transition.previousKind
        state.transport = .paused
        state.isBuffering = false
        let failure = PlaybackFailure(
            trackID: transition.currentID,
            message: "The new audio output could not be activated: "
                + error.localizedDescription
        )
        acceptRouteFailure(
            failure,
            currentItemID: transition.currentID,
            requestedRoute: transition.candidateRoute
                ?? audioRouteProvider.currentRoute(),
            routeGeneration: transition.expectedRouteGeneration
                ?? routeGeneration
        )
        state.audioPath = transition.previousAudioPath
        publishState()
    }

    private func routeTransitionIsCurrent(
        _ transition: PlaybackBackendTransition
    ) -> Bool {
        let routeIsCurrent = transition.expectedRouteGeneration.map {
            $0 == routeGeneration
        } ?? true
        return routeIsCurrent
            && transition.expectedIntent == playbackIntent
            && transition.currentID == state.currentTrack?.id
            && transition.currentID == state.queue?.currentTrackID
    }

    private func rejectSuperseded(
        _ transition: PlaybackBackendTransition
    ) {
        transition.requestedBackend.stop()
        guard transition.expectedRouteGeneration == routeGeneration,
              let candidateRoute = transition.candidateRoute,
              playbackIntent.currentItemID == state.currentTrack?.id,
              playbackIntent.currentItemID == state.queue?.currentTrackID,
              playbackIntent.transport == .playing
              || playbackIntent.transport == .paused
        else {
            return
        }
        pendingOutputRoute = candidateRoute
    }
}
