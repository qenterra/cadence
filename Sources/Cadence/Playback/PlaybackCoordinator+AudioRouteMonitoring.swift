import Foundation

extension PlaybackCoordinator {
    func receiveAudioRoute(_ route: AudioRouteSnapshot) {
        guard route != pendingOutputRoute else {
            return
        }
        guard routeTransitionTask != nil
            || routeFailureIsActive
            || route != outputRoute
        else {
            return
        }

        pendingOutputRoute = route
        routeGeneration += 1
        guard routeTransitionTask == nil else {
            return
        }

        routeTransitionTask = Task { @MainActor [weak self] in
            await self?.processPendingAudioRoutes()
        }
    }

    func waitForAudioRouteTransitions() async {
        while let routeTransitionTask {
            await routeTransitionTask.value
        }
    }

    private func processPendingAudioRoutes() async {
        while !Task.isCancelled, let route = pendingOutputRoute {
            let generation = routeGeneration
            pendingOutputRoute = nil
            await applyAudioRoute(route, generation: generation)
        }
        routeTransitionTask = nil
    }

    private func applyAudioRoute(
        _ route: AudioRouteSnapshot,
        generation: Int
    ) async {
        guard generation == routeGeneration else {
            return
        }
        guard let currentTrack = state.currentTrack else {
            outputRoute = route
            routeFailureIsActive = false
            publishState()
            return
        }
        guard let activeBackend = state.activeBackend else {
            reportAudioRouteFailure(
                "Playback has no active audio backend."
            )
            return
        }

        let requestedBackend = routeBackend(
            for: currentTrack,
            route: route
        )
        if activeBackend == requestedBackend {
            guard generation == routeGeneration else {
                return
            }
            outputRoute = route
            routeFailureIsActive = false
            state.failure = nil
            state.audioPath = audioPath(
                current: currentTrack,
                backend: activeBackend,
                next: nil,
                route: route
            )
            publishState()
            await prepareFollowingTrack()
            return
        }

        let didTransition = await transitionForAudioRoute(
            to: requestedBackend,
            route: route,
            generation: generation,
            reloadCurrentBackend: false
        )
        if !didTransition,
           generation == routeGeneration,
           !routeFailureIsActive {
            reportAudioRouteFailure(
                "No compatible playback backend is available."
            )
        }
    }

    func retryAudioRouteAndPlay() {
        receiveAudioRoute(audioRouteProvider.currentRoute())
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await waitForAudioRouteTransitions()
            guard
                !routeFailureIsActive,
                state.currentTrack != nil
            else {
                return
            }
            activeBackend?.play()
            state.transport = .playing
            publishState()
        }
    }

    private func reportAudioRouteFailure(_ message: String) {
        activeBackend?.pause()
        routeFailureIsActive = true
        state.transport = .paused
        state.isBuffering = false
        state.failure = PlaybackFailure(
            trackID: state.currentTrack?.id,
            message: "The new audio output could not be activated: "
                + message
        )
        publishState()
    }
}
