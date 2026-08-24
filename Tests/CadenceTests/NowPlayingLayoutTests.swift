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

    @Test("Lyric lines use static neutral tones without shimmer")
    func lyricLineVisualsAreStatic() {
        let active = ProductionLyricLineAppearance.resolve(
            isActive: true,
            isSynchronized: true
        )
        let inactive = ProductionLyricLineAppearance.resolve(
            isActive: false,
            isSynchronized: true
        )
        let unsynchronized = ProductionLyricLineAppearance.resolve(
            isActive: false,
            isSynchronized: false
        )

        #expect(active.tone == .primary)
        #expect(active.opacity == 1)
        #expect(!active.usesShimmer)
        #expect(inactive.tone == .secondary)
        #expect(inactive.opacity == 0.58)
        #expect(!inactive.usesShimmer)
        #expect(unsynchronized.tone == .primary)
        #expect(unsynchronized.opacity == 1)
        #expect(!unsynchronized.usesShimmer)
    }
}
