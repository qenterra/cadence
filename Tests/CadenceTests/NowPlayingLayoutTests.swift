@testable import Cadence
import Testing

struct NowPlayingLayoutTests {
    @Test
    func minimumWindowKeepsBothRegionsUsable() {
        let workspaceWidth = AdaptiveLayoutPolicy.minimumWindowSize.width
            - NavigationRailMetrics.expandedWidth
            - 1
        let layout = NowPlayingLayoutMetrics(totalWidth: workspaceWidth)

        #expect(layout.contextWidth >= 320)
        #expect(layout.panelWidth >= 480)
        #expect(layout.artworkSize >= 220)
        #expect(layout.contextWidth + layout.panelWidth + 1 == workspaceWidth)
    }

    @Test
    func defaultWindowUsesBalancedSplit() {
        let layout = NowPlayingLayoutMetrics(totalWidth: 1439)

        #expect(layout.contextWidth == 560)
        #expect(layout.panelWidth == 878)
        #expect(layout.artworkSize == 360)
    }

    @Test
    func wideWindowCapsContextAndArtwork() {
        let layout = NowPlayingLayoutMetrics(totalWidth: 1920)

        #expect(layout.contextWidth == 560)
        #expect(layout.panelWidth == 1359)
        #expect(layout.artworkSize == 360)
    }

    @Test("Unsupported widths still never invent horizontal space")
    func undersizedInputDoesNotOverflow() {
        let layout = NowPlayingLayoutMetrics(totalWidth: 500)

        #expect(layout.contextWidth + layout.panelWidth + 1 == 500)
    }
}
