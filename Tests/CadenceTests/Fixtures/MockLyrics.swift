@testable import Cadence
import Foundation

extension [TrackPreview.ID: LyricDocument] {
    static let mockLyrics: [TrackPreview.ID: LyricDocument] = {
        let synchronized = LyricDocument(
            trackID: 1,
            lines: [
                lyric("We kept the signal low", at: 7.2),
                lyric("While the city disappeared", at: 13.4),
                lyric("", at: nil),
                lyric("Static blooming in the dark", at: 20.8),
                lyric("Every frequency was clear", at: 27.1),
                lyric("Until the morning found us", at: 34.6),
                lyric("", at: nil),
                lyric("Past the edge of every frame", at: 42.5),
                lyric("We were listening for silence", at: 49.8),
                lyric("But the night still knew our names", at: 57.3),
                lyric("Hold the line until it fades", at: 65.9),
                lyric("Then let the distance answer", at: 73.4),
            ]
        )

        let unsynchronized = LyricDocument(
            trackID: 2,
            lines: LyricDocument.lines(
                fromPlainText: """
                The horizon turned to glass
                Underneath the quiet wires

                We were moving without maps
                Through a field of borrowed light
                """
            )
        )

        let partial = LyricDocument(
            trackID: 3,
            lines: [
                lyric("Transmission lines above us", at: 10.5),
                lyric("Drawing distances in blue", at: 17.2),
                lyric("", at: nil),
                lyric("Every message lost its ending", at: nil),
                lyric("Every echo sounded new", at: nil),
            ]
        )

        return [
            1: synchronized,
            2: unsynchronized,
            3: partial,
        ]
    }()

    private static func lyric(
        _ text: String,
        at time: TimeInterval?
    ) -> LyricLine {
        LyricLine(text: text, startTime: time)
    }
}
