import CoreGraphics
import SwiftUI

enum AdaptivePresentation: Sendable {
    case expanded
    case compressed
    case stacked
}

enum AdaptiveLayoutPolicy {
    static let minimumWindowSize = CGSize(width: 1080, height: 720)

    static func presentation(
        for contentWidth: CGFloat
    ) -> AdaptivePresentation {
        if contentWidth >= 1040 {
            return .expanded
        }
        if contentWidth >= 820 {
            return .compressed
        }
        return .stacked
    }

    static func animation(
        reduceMotion: Bool
    ) -> Animation? {
        reduceMotion
            ? nil
            : .easeInOut(duration: CadenceTheme.motionReplace)
    }
}
