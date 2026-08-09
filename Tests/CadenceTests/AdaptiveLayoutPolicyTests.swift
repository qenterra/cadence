@testable import Cadence
import CoreGraphics
import Testing

struct AdaptiveLayoutPolicyTests {
    @Test("The app window cannot shrink below the supported layout")
    func minimumWindowSize() {
        #expect(
            AdaptiveLayoutPolicy.minimumWindowSize
                == CGSize(width: 1080, height: 720)
        )
    }

    @Test("Content presentation follows one shared set of breakpoints")
    func presentationBreakpoints() {
        #expect(AdaptiveLayoutPolicy.presentation(for: 1200) == .expanded)
        #expect(AdaptiveLayoutPolicy.presentation(for: 900) == .compressed)
        #expect(AdaptiveLayoutPolicy.presentation(for: 780) == .stacked)
    }

    @Test("Optional motion is removed when Reduce Motion is enabled")
    func motionPolicy() {
        #expect(AdaptiveLayoutPolicy.animation(reduceMotion: true) == nil)
        #expect(AdaptiveLayoutPolicy.animation(reduceMotion: false) != nil)
    }
}
