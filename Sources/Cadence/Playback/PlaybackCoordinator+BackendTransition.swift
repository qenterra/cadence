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
}

private struct PlaybackBackendTransitionExpectation {
    let routeGeneration: Int?
}

extension PlaybackCoordinator {
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
                routeGeneration: generation
            ),
            reloadCurrentBackend: reloadCurrentBackend
        )
    }

    private func performBackendTransition(
        to requestedKind: PlaybackBackendKind,
        candidateRoute: AudioRouteSnapshot?,
        expectation: PlaybackBackendTransitionExpectation,
        reloadCurrentBackend: Bool
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
            wasPlaying: state.isPlaying,
            currentTime: presentationTime(),
            previousAudioPath: state.audioPath,
            candidateRoute: candidateRoute,
            expectedRouteGeneration: expectation.routeGeneration
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
            handleFailure(transition, after: error)
            return false
        }
    }

    private func begin(_ transition: PlaybackBackendTransition) {
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
            autoplay: transition.wasPlaying,
            volume: volume
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
        publishState()
    }

    private func handleFailure(
        _ transition: PlaybackBackendTransition,
        after error: Error
    ) {
        transition.requestedBackend.stop()
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
        publishState()
    }

    private func routeTransitionIsCurrent(
        _ transition: PlaybackBackendTransition
    ) -> Bool {
        transition.expectedRouteGeneration.map {
            $0 == routeGeneration
        } ?? true
    }
}
