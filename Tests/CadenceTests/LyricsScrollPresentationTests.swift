@testable import Cadence
import Foundation
import Testing

struct LyricsScrollPresentationTests {
    @Test("A new track resets once before following later active lines")
    func trackResetAndFollow() {
        let trackA = UUID()
        let trackB = UUID()
        let firstLine = UUID()
        let secondLine = UUID()
        var presentation = LyricsScrollPresentation()

        #expect(
            presentation.resolve(
                trackID: trackA,
                activeLineID: firstLine,
                reduceMotion: false
            ) == .top
        )
        #expect(
            presentation.resolve(
                trackID: trackA,
                activeLineID: firstLine,
                reduceMotion: false
            ) == .none
        )
        #expect(
            presentation.resolve(
                trackID: trackA,
                activeLineID: secondLine,
                reduceMotion: false
            ) == .activeLine(id: secondLine, duration: 0.32)
        )
        #expect(
            presentation.resolve(
                trackID: trackB,
                activeLineID: secondLine,
                reduceMotion: false
            ) == .top
        )
    }

    @Test("Reduce Motion follows immediately without losing seeking")
    func reduceMotionFollow() {
        let trackID = UUID()
        let firstLine = UUID()
        let secondLine = UUID()
        var presentation = LyricsScrollPresentation()

        _ = presentation.resolve(
            trackID: trackID,
            activeLineID: firstLine,
            reduceMotion: true
        )

        #expect(
            presentation.resolve(
                trackID: trackID,
                activeLineID: secondLine,
                reduceMotion: true
            ) == .activeLine(id: secondLine, duration: 0)
        )
    }
}
