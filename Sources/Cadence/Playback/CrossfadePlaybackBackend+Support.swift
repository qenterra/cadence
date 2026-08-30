import AVFoundation
import Foundation

enum CrossfadePlaybackSlot: Equatable {
    case primary
    case secondary

    var other: Self {
        self == .primary ? .secondary : .primary
    }

    @MainActor
    func backend(
        in owner: CrossfadePlaybackBackend
    ) -> any PlaybackBackend {
        switch self {
        case .primary: owner.primary
        case .secondary: owner.secondary
        }
    }
}

extension CrossfadePlaybackBackend: PlaybackAirPlayPlayerProviding {
    var bassLevelProvider: (any PlaybackBassLevelProviding)? {
        activeBackend.bassLevelProvider
    }

    var airPlayPlayer: AVPlayer? {
        (activeBackend as? any PlaybackAirPlayPlayerProviding)?.airPlayPlayer
    }

    func setNormalizationGain(_ gain: Float) {
        activeBackend.setNormalizationGain(gain)
    }

    func setPresentationGain(
        _ gain: Float,
        duration: Duration
    ) async {
        await activeBackend.setPresentationGain(gain, duration: duration)
    }

    func resetBassAnalysis() {
        activeBackend.resetBassAnalysis()
    }
}
