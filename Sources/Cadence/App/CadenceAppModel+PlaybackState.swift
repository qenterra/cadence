import Foundation

extension CadenceAppModel {
    var isPlaying: Bool {
        get {
            playbackCoordinator?.state.isPlaying ?? previewIsPlaying
        }
        set {
            guard let playbackCoordinator else {
                previewIsPlaying = newValue
                return
            }
            if newValue {
                playbackCoordinator.play()
            } else {
                playbackCoordinator.pause()
            }
        }
    }

    var isShuffleEnabled: Bool {
        get {
            playbackCoordinator?.isShuffleEnabled
                ?? previewIsShuffleEnabled
        }
        set {
            guard let playbackCoordinator else {
                previewIsShuffleEnabled = newValue
                return
            }
            playbackCoordinator.setShuffleEnabled(newValue)
        }
    }

    var repeatMode: RepeatMode {
        get {
            playbackCoordinator?.repeatMode ?? previewRepeatMode
        }
        set {
            guard let playbackCoordinator else {
                previewRepeatMode = newValue
                return
            }
            playbackCoordinator.repeatMode = newValue
        }
    }

    var progress: Double {
        get {
            playbackCoordinator?.progress ?? previewProgress
        }
        set {
            guard let playbackCoordinator else {
                previewProgress = newValue
                return
            }
            Task {
                await playbackCoordinator.seek(toProgress: newValue)
            }
        }
    }

    var volume: Double {
        get {
            playbackCoordinator.map { Double($0.volume) }
                ?? previewVolume
        }
        set {
            let clampedVolume = min(max(newValue, 0), 1)
            if clampedVolume > 0 {
                mutedVolume = nil
            }
            guard let playbackCoordinator else {
                previewVolume = clampedVolume
                return
            }
            playbackCoordinator.setVolume(Float(clampedVolume))
        }
    }

    func toggleMute() {
        if volume > 0 {
            mutedVolume = volume
            volume = 0
        } else {
            volume = mutedVolume ?? 0.72
        }
    }

    var currentPlaybackTrack: PlaybackTrack? {
        playbackCoordinator?.state.currentTrack
    }

    var playbackCurrentTime: TimeInterval {
        playbackCoordinator?.state.currentTime
            ?? (currentTrack?.duration ?? 0) * previewProgress
    }

    func playbackPresentationTime(
        atHostUptime hostUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> TimeInterval {
        playbackCoordinator?.presentationTime(
            atHostUptime: hostUptime
        ) ?? playbackCurrentTime
    }

    var playbackDuration: TimeInterval {
        playbackCoordinator?.state.duration
            ?? currentTrack?.duration
            ?? 0
    }

    var hasCurrentPlaybackItem: Bool {
        currentPlaybackTrack != nil || currentTrack != nil
    }

    @discardableResult
    func handlePlaybackShortcut() -> Bool {
        guard hasCurrentPlaybackItem else {
            return false
        }
        isPlaying.toggle()
        return true
    }

    func seekPlayback(
        toProgress progress: Double
    ) async {
        guard let playbackCoordinator else {
            previewProgress = min(max(progress, 0), 1)
            return
        }
        await playbackCoordinator.seek(toProgress: progress)
    }
}
