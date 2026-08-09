import Foundation

extension PlaybackCoordinator {
    func setQualityProfile(_ profile: AudioQualityProfile) async {
        guard profile != qualityProfile else {
            return
        }
        audioConfigurationGeneration &+= 1
        let generation = audioConfigurationGeneration
        let previousProfile = qualityProfile
        qualityProfile = profile
        qualityProfileStore.save(profile)
        await cancelSupersededAudioConfigurationTransition()
        await waitForAudioRouteTransitions()
        guard generation == audioConfigurationGeneration else {
            return
        }
        guard let currentTrack = state.currentTrack else {
            return
        }
        let requestedKind = routeBackend(for: currentTrack)
        guard requestedKind != state.activeBackend else {
            activeBackend?.setReplayGain(replayGain(for: currentTrack))
            restoreSupersededConfigurationTransitionIfNeeded()
            await prepareFollowingTrack()
            refreshAudioPath(
                next: followingTrackID.flatMap { resolvedTracks[$0] }
            )
            return
        }
        guard await runAudioConfigurationTransition(
            to: requestedKind,
            generation: generation
        ) else {
            guard generation == audioConfigurationGeneration else {
                return
            }
            qualityProfile = previousProfile
            qualityProfileStore.save(previousProfile)
            return
        }
    }

    func setStereoSpatializationEnabled(_ enabled: Bool) async {
        guard enabled != stereoSpatializationEnabled else {
            return
        }
        audioConfigurationGeneration &+= 1
        let generation = audioConfigurationGeneration
        let previousValue = stereoSpatializationEnabled
        stereoSpatializationEnabled = enabled
        qualityProfileStore.saveStereoSpatializationEnabled(enabled)
        await cancelSupersededAudioConfigurationTransition()
        await waitForAudioRouteTransitions()
        guard generation == audioConfigurationGeneration else {
            return
        }
        guard
            qualityProfile == .immersive,
            let currentTrack = state.currentTrack
        else {
            publishState()
            return
        }
        let requestedKind = routeBackend(for: currentTrack)
        guard requestedKind != state.activeBackend else {
            restoreSupersededConfigurationTransitionIfNeeded()
            publishState()
            return
        }
        guard await runAudioConfigurationTransition(
            to: requestedKind,
            generation: generation
        ) else {
            guard generation == audioConfigurationGeneration else {
                return
            }
            stereoSpatializationEnabled = previousValue
            qualityProfileStore.saveStereoSpatializationEnabled(previousValue)
            return
        }
    }

    func waitForAudioConfigurationTransitions() async {
        while let audioConfigurationTransitionTask {
            _ = await audioConfigurationTransitionTask.value
        }
    }
}

private extension PlaybackCoordinator {
    func cancelSupersededAudioConfigurationTransition() async {
        guard let transition = audioConfigurationTransitionTask else {
            return
        }
        transition.cancel()
        _ = await transition.value
    }

    func restoreSupersededConfigurationTransitionIfNeeded() {
        guard state.transport == .loading,
              let wasPlaying = configurationTransitionWasPlaying
        else {
            return
        }
        state.transport = wasPlaying ? .playing : .paused
        state.isBuffering = false
        state.failure = nil
        configurationTransitionWasPlaying = nil
    }

    func runAudioConfigurationTransition(
        to requestedKind: PlaybackBackendKind,
        generation: Int
    ) async -> Bool {
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return false
            }
            let result = await transitionBackend(
                to: requestedKind,
                configurationGeneration: generation
            )
            if audioConfigurationTransitionGeneration == generation {
                audioConfigurationTransitionTask = nil
                audioConfigurationTransitionGeneration = nil
            }
            return result
        }
        audioConfigurationTransitionTask = task
        audioConfigurationTransitionGeneration = generation
        return await task.value
    }
}
