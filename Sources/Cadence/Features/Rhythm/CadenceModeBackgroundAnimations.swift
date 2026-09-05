import Foundation

enum CadenceModeGradientTimeline {
    static func elapsedTime(
        startedAt: TimeInterval,
        currentTime: TimeInterval,
        isAnimated: Bool
    ) -> Float {
        guard isAnimated else {
            return 0
        }
        return Float(max(currentTime - startedAt, 0))
    }
}
