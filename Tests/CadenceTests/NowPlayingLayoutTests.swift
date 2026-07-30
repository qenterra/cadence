@testable import Cadence
import Testing

struct NowPlayingLayoutTests {
    @Test
    func minimumWindowKeepsBothRegionsUsable() {
        let layout = NowPlayingLayoutMetrics(totalWidth: 1007)

        #expect(layout.contextWidth >= 340)
        #expect(layout.panelWidth >= 520)
        #expect(layout.artworkSize >= 220)
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

    @Test
    func undersizedInputResolvesToSupportedMinimum() {
        let layout = NowPlayingLayoutMetrics(totalWidth: 500)

        #expect(layout.contextWidth == 340)
        #expect(layout.panelWidth == 520)
    }
}
