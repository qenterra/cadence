import Foundation

extension PlaybackCoordinator {
    func refreshPreferences() {
        let seekInterval = CadencePreferences.seekInterval(
            in: preferences
        ).seconds
        systemMediaSession.setSkipInterval(seekInterval)

        if !preferences.bool(
            forKey: CadencePreferences.Keys.restoresQueue
        ) {
            playbackSessionStore.clear()
        } else {
            persistPlaybackSession()
        }

        guard let track = state.currentTrack else {
            return
        }
        activeBackend?.setNormalizationGain(
            normalizationGain(for: track)
        )
    }

    func normalizationGain(
        for track: PlaybackTrack
    ) -> Float {
        PlaybackNormalization.gain(
            mode: CadencePreferences.volumeNormalization(in: preferences),
            trackGainDecibels: track.replayGainTrackGain,
            trackPeak: track.replayGainTrackPeak
        )
    }

    func persistPlaybackSession() {
        guard persistsPlaybackSession else {
            return
        }
        guard preferences.bool(
            forKey: CadencePreferences.Keys.restoresQueue
        ) else {
            playbackSessionStore.clear()
            return
        }
        guard let queue = state.queue,
              queue.source != .externalFiles,
              queue.currentTrackID != nil
        else {
            playbackSessionStore.clear()
            return
        }
        playbackSessionStore.save(
            PlaybackSessionSnapshot(
                queue: queue,
                repeatMode: repeatMode,
                canonicalTrackIDs: canonicalOrder,
                currentTime: state.currentTime
            )
        )
    }

    @discardableResult
    func restorePersistedSession(
        validTrackIDs: Set<UUID>
    ) async -> Bool {
        guard !sessionRestoreAttempted else {
            return state.currentTrack != nil
        }
        sessionRestoreAttempted = true
        guard preferences.bool(
            forKey: CadencePreferences.Keys.restoresQueue
        ) else {
            playbackSessionStore.clear()
            return false
        }
        guard
            let snapshot = playbackSessionStore.load(),
            let restored = snapshot.restoredState(
                validTrackIDs: validTrackIDs
            )
        else {
            playbackSessionStore.clear()
            return false
        }

        activateSystemMediaSession()
        stop(resetQueue: false)
        canonicalOrder = restored.canonicalTrackIDs
        state.queue = restored.queue
        repeatMode = snapshot.repeatMode
        state.currentTime = snapshot.currentTime
        failedTrackIDs = []
        let didRestore = await loadCurrent(
            startTime: snapshot.currentTime,
            autoplay: false
        )
        if !didRestore {
            playbackSessionStore.clear()
        }
        return didRestore
    }

    func acceptedIntentForRouteRecovery(
        currentTrackID: UUID
    ) -> PlaybackIntentAuthority {
        guard visibleRouteFailureAuthority != nil,
              routeRecoveryShouldResume,
              preferences.bool(
                  forKey: CadencePreferences.Keys.resumesAfterRouteRecovery
              ),
              playbackIntent.currentItemID == currentTrackID
        else {
            return playbackIntent
        }
        routeRecoveryShouldResume = false
        return advancePlaybackIntent(
            currentItemID: currentTrackID,
            transport: .playing
        )
    }

    func finishRouteRecovery() {
        routeRecoveryShouldResume = false
    }
}
