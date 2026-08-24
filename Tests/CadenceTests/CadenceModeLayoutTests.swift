@testable import Cadence
import CoreGraphics
import Testing

struct CadenceModeLayoutTests {
    @Test("Cadence Mode artwork is centered and leaves five lyric slots visible")
    func cadenceModeCompositionFitsMinimumWindow() throws {
        let canvasSize = CGSize(width: 1080, height: 720)
        let context = NowPlayingLayoutMetrics(
            totalWidth: canvasSize.width
        ).contextWidth
        let layout = CadenceModeLayout(
            canvasSize: canvasSize,
            contextWidth: context
        )
        let lyricsFrame = try #require(layout.modeLyricsFrame)

        #expect(layout.modeArtworkFrame.midX == canvasSize.width / 2)
        #expect((260 ... 420).contains(layout.modeArtworkFrame.width))
        #expect(lyricsFrame.minY > layout.modeArtworkFrame.maxY)
        #expect(lyricsFrame.maxY <= canvasSize.height - 24)
        #expect(layout.modeLyricSlotHeight >= 36)
        #expect(lyricsFrame.height >= layout.modeLyricSlotHeight * 5)
    }

    @Test("Cadence Mode keeps fullscreen artwork compact for effects")
    func cadenceModeCompositionUsesLargeDisplay() throws {
        let canvasSize = CGSize(width: 2560, height: 1400)
        let context = NowPlayingLayoutMetrics(
            totalWidth: canvasSize.width
        ).contextWidth
        let layout = CadenceModeLayout(
            canvasSize: canvasSize,
            contextWidth: context
        )
        let lyricsFrame = try #require(layout.modeLyricsFrame)

        #expect(layout.modeArtworkFrame.width > 420)
        #expect(layout.modeArtworkFrame.width <= 560)
        #expect(layout.modeArtworkFrame.minY >= 24)
        #expect(lyricsFrame.minY > layout.modeArtworkFrame.maxY)
        #expect(lyricsFrame.maxY <= canvasSize.height - 24)
    }

    @Test("Cadence Mode reserves only the enabled identity and lyrics slots")
    func optionalContentFrames() {
        let canvasSize = CGSize(width: 1440, height: 900)

        for showsLyrics in [false, true] {
            for showsTrackInformation in [false, true] {
                let options = CadenceModeOptions(
                    isEnabled: true,
                    reactsToBass: true,
                    showsLyrics: showsLyrics,
                    showsTrackInformation: showsTrackInformation,
                    staysActive: false
                )
                let layout = CadenceModeLayout(
                    canvasSize: canvasSize,
                    contextWidth: 576,
                    options: options
                )

                #expect((layout.modeLyricsFrame != nil) == showsLyrics)
                #expect(
                    (layout.modeIdentityFrame != nil)
                        == showsTrackInformation
                )
                #expect(layout.modeArtworkFrame.width <= 560)
                #expect(layout.modeArtworkFrame.minX >= 24)
                #expect(layout.modeArtworkFrame.maxX <= canvasSize.width - 24)

                if let identity = layout.modeIdentityFrame {
                    #expect(identity.minY > layout.modeArtworkFrame.maxY)
                    #expect(!identity.intersects(layout.modeArtworkFrame))
                }
                if let lyrics = layout.modeLyricsFrame {
                    #expect(lyrics.minY > layout.modeArtworkFrame.maxY)
                    #expect(!lyrics.intersects(layout.modeArtworkFrame))
                    #expect(lyrics.maxY <= canvasSize.height - 24)
                }
            }
        }
    }

    @Test("The standard artwork frame matches the padded context layout")
    func standardArtworkMatchesContext() {
        let canvasSize = CGSize(width: 1440, height: 868)
        let context = NowPlayingLayoutMetrics(
            totalWidth: canvasSize.width
        ).contextWidth
        let layout = CadenceModeLayout(
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
        let layout = CadenceModeLayout(
            canvasSize: canvasSize,
            contextWidth: 432
        )

        for isCadenceModeActive in [false, true] {
            let artworkFrame = isCadenceModeActive
                ? layout.modeArtworkFrame
                : layout.standardArtworkFrame
            let left = layout.emitterOrigin(
                lane: .left,
                isCadenceModeActive: isCadenceModeActive
            )
            let right = layout.emitterOrigin(
                lane: .right,
                isCadenceModeActive: isCadenceModeActive
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
                isCadenceModeActive: isCadenceModeActive
            )
            #expect((0 ... 1).contains(normalized.x))
            #expect((0 ... 1).contains(normalized.y))
        }
    }

    @Test("Cadence Mode composition remains bounded in a short workspace")
    func cadenceModeCompositionFitsShortWorkspace() throws {
        let canvasSize = CGSize(width: 1080, height: 600)
        let layout = CadenceModeLayout(
            canvasSize: canvasSize,
            contextWidth: 432
        )
        let lyricsFrame = try #require(layout.modeLyricsFrame)

        #expect(layout.modeArtworkFrame.minY >= 24)
        #expect(lyricsFrame.maxY <= canvasSize.height - 24)
        #expect(layout.modeLyricSlotHeight >= 32)
    }
}
