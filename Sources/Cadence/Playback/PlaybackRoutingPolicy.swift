import Foundation

struct PlaybackRoutingRequest: Sendable {
    let track: PlaybackTrack
    let profile: AudioQualityProfile
    let route: AudioRouteSnapshot
    let stereoSpatializationEnabled: Bool
}

enum PlaybackRoutingPolicy {
    static func backend(
        for request: PlaybackRoutingRequest
    ) -> PlaybackBackendKind {
        if request.route.transport == .airPlay {
            return .native
        }

        switch request.track.spatialFormat {
        case .dolbyAtmos, .multichannel:
            return .native
        case .unknown, .stereo:
            break
        }

        if request.profile == .immersive,
           request.stereoSpatializationEnabled {
            return .native
        }

        return supportsPCM(request.track) ? .pcm : .native
    }

    static func supportsPCM(_ track: PlaybackTrack) -> Bool {
        guard track.channelCount == 1 || track.channelCount == 2 else {
            return false
        }
        return [
            "aif",
            "aiff",
            "alac",
            "flac",
            "lpcm",
            "pcm",
            "wav",
        ].contains(track.codec.lowercased())
            || [
                "aif",
                "aiff",
                "flac",
                "wav",
            ].contains(track.container.lowercased())
    }
}
