@testable import Cadence
import CoreGraphics
import Testing

struct WindowContentLayoutTests {
    @Test("A root beneath the toolbar is placed in the content layout rect")
    func obscuredRootPlacement() {
        let placement = WindowContentLayoutMetrics.placement(
            containerRect: CGRect(x: 0, y: 0, width: 1080, height: 884),
            contentLayoutRect: CGRect(x: 0, y: 40, width: 1080, height: 844)
        )

        #expect(placement.offset == CGSize(width: 0, height: 40))
        #expect(placement.size == CGSize(width: 1080, height: 844))
    }

    @Test("A root already inside the native safe area is not shifted twice")
    func safeRootPlacement() {
        let placement = WindowContentLayoutMetrics.placement(
            containerRect: CGRect(x: 0, y: 40, width: 1080, height: 844),
            contentLayoutRect: CGRect(x: 0, y: 40, width: 1080, height: 844)
        )

        #expect(placement.offset == .zero)
        #expect(placement.size == CGSize(width: 1080, height: 844))
    }
}
