@testable import Cadence
import CoreGraphics
import Testing

struct RhythmFocusLayoutTests {
    @Test("Focus artwork is centered and leaves five lyric slots visible")
    func focusCompositionFitsMinimumWindow() {
        let canvasSize = CGSize(width: 1080, height: 720)
        let context = NowPlayingLayoutMetrics(
            totalWidth: canvasSize.width
        ).contextWidth
        let layout = RhythmFocusLayout(
            canvasSize: canvasSize,
            contextWidth: context
        )

        #expect(layout.focusArtworkFrame.midX == canvasSize.width / 2)
        #expect((260 ... 420).contains(layout.focusArtworkFrame.width))
        #expect(layout.focusLyricsFrame.minY > layout.focusArtworkFrame.maxY)
        #expect(layout.focusLyricsFrame.maxY <= canvasSize.height - 24)
        #expect(layout.focusLyricSlotHeight >= 36)
        #expect(layout.focusLyricsFrame.height >= layout.focusLyricSlotHeight * 5)
    }

    @Test("The standard artwork frame matches the padded context layout")
    func standardArtworkMatchesContext() {
        let canvasSize = CGSize(width: 1440, height: 868)
        let context = NowPlayingLayoutMetrics(
            totalWidth: canvasSize.width
        ).contextWidth
        let layout = RhythmFocusLayout(
            canvasSize: canvasSize,
            contextWidth: context
        )

        #expect(layout.standardArtworkFrame.minX == 42)
        #expect(layout.standardArtworkFrame.minY == 42)
        #expect(layout.standardArtworkFrame.width == 420)
        #expect(layout.standardArtworkFrame.maxX <= context - 42)
    }

    @Test("Z and X emit from opposite visible side edges of the artwork")
    func emitterOriginsStayInsideArtwork() {
        let canvasSize = CGSize(width: 1080, height: 720)
        let layout = RhythmFocusLayout(
            canvasSize: canvasSize,
            contextWidth: 432
        )

        for isFocused in [false, true] {
            let artworkFrame = isFocused
                ? layout.focusArtworkFrame
                : layout.standardArtworkFrame
            let left = layout.emitterOrigin(
                lane: .left,
                isFocused: isFocused
            )
            let right = layout.emitterOrigin(
                lane: .right,
                isFocused: isFocused
            )

            #expect(artworkFrame.contains(left))
            #expect(artworkFrame.contains(right))
            #expect(left.x < right.x)
            #expect(left.y == right.y)
            #expect(left.x <= artworkFrame.minX + artworkFrame.width * 0.12)
            #expect(right.x >= artworkFrame.maxX - artworkFrame.width * 0.12)
            #expect(
                (artworkFrame.minY + artworkFrame.height * 0.35
                    ... artworkFrame.minY + artworkFrame.height * 0.65)
                    .contains(left.y)
            )

            let normalized = layout.normalizedEmitterOrigin(
                lane: .right,
                isFocused: isFocused
            )
            #expect((0 ... 1).contains(normalized.x))
            #expect((0 ... 1).contains(normalized.y))
        }
    }

    @Test("Focus composition remains bounded in a short workspace")
    func focusCompositionFitsShortWorkspace() {
        let canvasSize = CGSize(width: 1080, height: 600)
        let layout = RhythmFocusLayout(
            canvasSize: canvasSize,
            contextWidth: 432
        )

        #expect(layout.focusArtworkFrame.minY >= 24)
        #expect(layout.focusLyricsFrame.maxY <= canvasSize.height - 24)
        #expect(layout.focusLyricSlotHeight >= 32)
    }
}
