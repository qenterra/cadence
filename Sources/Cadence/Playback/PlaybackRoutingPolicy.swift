import Foundation

struct PlaybackRoutingRequest: Sendable {
    let track: PlaybackTrack
    let route: AudioRouteSnapshot
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
