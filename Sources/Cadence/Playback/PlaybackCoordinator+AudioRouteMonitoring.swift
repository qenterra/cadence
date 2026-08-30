import Foundation

extension PlaybackCoordinator {
    func receiveAudioRoute(_ route: AudioRouteSnapshot) {
        guard route != pendingOutputRoute else {
            return
        }
        guard routeTransitionTask != nil
            || visibleRouteFailureAuthority != nil
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
            invalidateRouteFailureAuthority()
            publishState()
            return
        }
        guard let activeBackend = state.activeBackend else {
            reportAudioRouteFailure(
                "Playback has no active audio backend.",
                route: route,
                generation: generation
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
            let acceptedIntent = acceptedIntentForRouteRecovery(
                currentTrackID: currentTrack.id
            )
            let wasPlaying = state.isPlaying
            invalidateBassState()
            outputRoute = route
            clearVisibleRouteFailureAuthority(
                currentItemID: currentTrack.id
            )
            state.transport = acceptedIntent.transport.state
            if acceptedIntent.transport != .failed {
                state.failure = nil
            }
            state.audioPath = audioPath(
                current: currentTrack,
                backend: activeBackend,
                next: nil,
                route: route
            )
            if acceptedIntent.transport == .playing {
                if !wasPlaying {
                    self.activeBackend?.play()
                }
                activateBassSourceForCurrentTrack()
            }
            publishState()
            finishRouteRecovery()
            await prepareFollowingTrack(expectedIntent: acceptedIntent)
            return
        }

        _ = acceptedIntentForRouteRecovery(
            currentTrackID: currentTrack.id
        )
        let transitionResult = await transitionForAudioRoute(
            to: requestedBackend,
            route: route,
            generation: generation,
            reloadCurrentBackend: false
        )
        if case .failed = transitionResult,
           generation == routeGeneration,
           visibleRouteFailureAuthority == nil {
            reportAudioRouteFailure(
                "No compatible playback backend is available.",
                route: route,
                generation: generation
            )
        }
    }

    func retryAudioRouteAndPlay(
        expectedIntent: PlaybackIntentAuthority
    ) {
        receiveAudioRoute(audioRouteProvider.currentRoute())
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await waitForAudioRouteTransitions()
            guard
                playbackIntent == expectedIntent,
                visibleRouteFailureAuthority == nil,
                state.currentTrack?.id == expectedIntent.currentItemID,
                expectedIntent.transport == .playing
            else {
                return
            }
            if state.transport != .playing {
                state.transport = .playing
                activeBackend?.play()
                activateBassSourceForCurrentTrack()
                publishState()
            }
        }
    }

    private func reportAudioRouteFailure(
        _ message: String,
        route: AudioRouteSnapshot,
        generation: Int
    ) {
        invalidateBassState()
        activeBackend?.pause()
        routeRecoveryShouldResume = playbackIntent.transport == .playing
        advancePlaybackIntent(
            currentItemID: state.currentTrack?.id,
            transport: .paused
        )
        state.transport = .paused
        state.isBuffering = false
        let failure = PlaybackFailure(
            trackID: state.currentTrack?.id,
            message: "The new audio output could not be activated: "
                + message
        )
        if let currentItemID = state.currentTrack?.id {
            acceptRouteFailure(
                failure,
                currentItemID: currentItemID,
                requestedRoute: route,
                routeGeneration: generation
            )
        } else {
            invalidateRouteFailureAuthority()
            state.failure = failure
        }
        publishState()
    }
}
