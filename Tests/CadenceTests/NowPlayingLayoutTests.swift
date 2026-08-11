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

    @Test("Lyric motion spans the exact synchronized line interval")
    func synchronizedLyricDuration() {
        #expect(
            ProductionLyricMotion.duration(
                startTime: 5,
                nextStartTime: 11,
                trackDuration: 60
            ) == 6
        )
    }

    @Test("The final lyric line uses the remaining track duration")
    func finalLyricDuration() {
        #expect(
            ProductionLyricMotion.duration(
                startTime: 30,
                nextStartTime: nil,
                trackDuration: 42
            ) == 12
        )
    }

    @Test("Untimed lyrics never receive progress motion")
    func untimedLyricDuration() {
        #expect(
            ProductionLyricMotion.duration(
                startTime: nil,
                nextStartTime: nil,
                trackDuration: 42
            ) == 0
        )
    }

    @Test("Only inactive synchronized lyrics use a soft blur")
    func inactiveLyricBlur() {
        #expect(
            ProductionLyricLineAppearance.blurRadius(
                isActive: false,
                isSynchronized: true,
                isIncreasedContrast: false
            ) == 0.7
        )
        #expect(
            ProductionLyricLineAppearance.blurRadius(
                isActive: true,
                isSynchronized: true,
                isIncreasedContrast: false
            ) == 0
        )
        #expect(
            ProductionLyricLineAppearance.blurRadius(
                isActive: false,
                isSynchronized: false,
                isIncreasedContrast: false
            ) == 0
        )
        #expect(
            ProductionLyricLineAppearance.blurRadius(
                isActive: false,
                isSynchronized: true,
                isIncreasedContrast: true
            ) == 0
        )
    }
}
