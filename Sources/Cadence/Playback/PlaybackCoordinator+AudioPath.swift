import Foundation

extension PlaybackCoordinator {
    func audioPath(
        current: PlaybackTrack,
        backend: PlaybackBackendKind,
        next: ResolvedPlaybackTrack?,
        route: AudioRouteSnapshot? = nil
    ) -> AudioPathSnapshot {
        AudioPathSnapshot(
            codec: current.codec,
            container: current.container,
            sourceBitDepth: current.bitDepth,
            sourceSampleRate: current.sampleRate,
            sourceChannelCount: current.channelCount,
            sourceSpatialFormat: current.spatialFormat,
            backend: backend,
            rendererSampleRate: backend == .pcm ? current.sampleRate : nil,
            rendererChannelCount: backend == .pcm ? current.channelCount : nil,
            outputRoute: route ?? outputRoute,
            nextTransitionIsGapless: next.map {
                backend == .pcm
                    && PlaybackRoutingPolicy.supportsPCM($0.track)
                    && $0.track.sampleRate == current.sampleRate
                    && $0.track.channelCount == current.channelCount
            } ?? false
        )
    }

    func refreshAudioPath(
        next: ResolvedPlaybackTrack?
    ) {
        guard
            let current = state.currentTrack,
            let backend = state.activeBackend
        else {
            return
        }
        state.audioPath = audioPath(
            current: current,
            backend: backend,
            next: next
        )
        publishState()
    }
}
