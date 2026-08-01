@testable import Cadence
import CoreGraphics
import Testing

struct GuideLayoutTests {
    @Test("Automatic guide cards stay inside the window and outside the target")
    func automaticCardPlacement() {
        for scenario in GuideLayoutScenario.representative {
            let frame = GuideOverlayLayout.cardFrame(
                viewportSize: scenario.viewportSize,
                target: scenario.target,
                placement: .automatic
            )
            let safeViewport = CGRect(
                origin: .zero,
                size: scenario.viewportSize
            ).insetBy(
                dx: GuideOverlayLayout.margin,
                dy: GuideOverlayLayout.margin
            )

            #expect(safeViewport.contains(frame), Comment(rawValue: scenario.name))
            #expect(!frame.intersects(scenario.target), Comment(rawValue: scenario.name))
        }
    }

    @Test("Guide spotlight expansion respects a safe window margin")
    func spotlightSafeArea() {
        let rect = GuideOverlayLayout.spotlightRect(
            rawRect: CGRect(x: 0, y: 0, width: 320, height: 70),
            viewportSize: CGSize(width: 1512, height: 886)
        )

        #expect(rect?.minX == GuideOverlayLayout.spotlightMargin)
        #expect(rect?.minY == GuideOverlayLayout.spotlightMargin)
        #expect(rect?.width == 320 + GuideOverlayLayout.spotlightPadding)
    }

    @Test("Guide card reserves a bounded scrollable content height")
    func boundedCardHeight() {
        #expect(GuideOverlayLayout.cardSize.height == 320)

        let frame = GuideOverlayLayout.cardFrame(
            viewportSize: CGSize(width: 1080, height: 720),
            target: nil,
            placement: .center
        )
        #expect(frame.height == 320)
    }

    @Test("Collapsed rail selection keeps the required trailing inset")
    func collapsedRailSelectionWidth() {
        let rowWidth = NavigationRailMetrics.rowWidth(isExpanded: false)

        #expect(rowWidth == 52)
        #expect(
            NavigationRailMetrics.totalWidth(isExpanded: false) - rowWidth
                == NavigationRailMetrics.horizontalInset * 2
        )
    }
}

struct GuideLayoutScenario: Sendable, CustomTestStringConvertible {
    let name: String
    let viewportSize: CGSize
    let target: CGRect

    var testDescription: String {
        name
    }

    static let representative = [
        GuideLayoutScenario(
            name: "sidebar",
            viewportSize: CGSize(width: 1512, height: 886),
            target: CGRect(x: 10, y: 14, width: 52, height: 442)
        ),
        GuideLayoutScenario(
            name: "library header",
            viewportSize: CGSize(width: 1512, height: 886),
            target: CGRect(x: 73, y: 12, width: 1427, height: 76)
        ),
        GuideLayoutScenario(
            name: "import title",
            viewportSize: CGSize(width: 1512, height: 886),
            target: CGRect(x: 98, y: 24, width: 260, height: 58)
        ),
        GuideLayoutScenario(
            name: "player transport",
            viewportSize: CGSize(width: 1512, height: 886),
            target: CGRect(x: 340, y: 804, width: 832, height: 60)
        ),
    ]
}
