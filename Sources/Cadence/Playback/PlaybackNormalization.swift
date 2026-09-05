import Foundation

enum PlaybackNormalization {
    static func gain(
        mode: VolumeNormalizationMode,
        trackGainDecibels: Double?,
        trackPeak: Double?
    ) -> Float {
        guard mode == .track, let trackGainDecibels,
              trackGainDecibels.isFinite
        else {
            return 1
        }

        var linearGain = pow(10, trackGainDecibels / 20)
        if let trackPeak, trackPeak.isFinite, trackPeak > 0 {
            linearGain = min(linearGain, 1 / trackPeak)
        }
        return Float(min(max(linearGain, 0), 4))
    }
}
