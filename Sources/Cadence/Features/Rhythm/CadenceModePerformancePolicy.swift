import Foundation
import QuartzCore

enum CadenceModePerformancePolicy {
    static let minimumSupportedFramesPerSecond = 60
    static let preferredProMotionFramesPerSecond = 110
    static let maximumFrameDuration: TimeInterval = 0.025
    static let maximumInputLatency: TimeInterval = 0.010

    static func minimumDeliveredFramesPerSecond(
        displayMaximumFramesPerSecond: Int
    ) -> Double {
        if displayMaximumFramesPerSecond >= 100 {
            return Double(preferredProMotionFramesPerSecond)
        }
        return Double(
            min(
                displayMaximumFramesPerSecond,
                minimumSupportedFramesPerSecond
            )
        )
    }

    static func animationFrameRateRange(
        displayMaximumFramesPerSecond: Int,
        contentMaximumFramesPerSecond: Int? = nil
    ) -> CAFrameRateRange {
        let displayMaximum = max(displayMaximumFramesPerSecond, 1)
        let maximum = min(
            displayMaximum,
            contentMaximumFramesPerSecond ?? displayMaximum
        )
        let requestedMinimum = min(
            minimumSupportedFramesPerSecond,
            maximum
        )
        return CAFrameRateRange(
            minimum: Float(requestedMinimum),
            maximum: Float(maximum),
            preferred: Float(maximum)
        )
    }
}
