@testable import Cadence
import Foundation
import Testing

struct LyricsDomainTests {
    @Test("Timing status distinguishes every supported lyric state")
    func timingStatus() {
        #expect(LyricDocument(trackID: 1, lines: []).timingStatus == .missing)
        #expect(
            document(
                texts: ["First", "", "Second"],
                times: [nil, nil, nil]
            ).timingStatus == .unsynchronized
        )
        #expect(
            document(
                texts: ["First", "Second"],
                times: [1, nil]
            ).timingStatus == .partiallySynchronized
        )
        #expect(
            document(
                texts: ["First", "", "Second"],
                times: [1, nil, 3]
            ).timingStatus == .synchronized
        )
    }

    @Test("Active line lookup uses line timestamps and their boundaries")
    func activeLineLookup() throws {
        let lyrics = document(
            texts: ["First", "Second", "Third"],
            times: [4, 8, 12]
        )
        let first = try #require(lyrics.lines.first)
        let second = try #require(lyrics.lines.dropFirst().first)
        let third = try #require(lyrics.lines.last)

        #expect(lyrics.activeLine(at: 0) == nil)
        #expect(lyrics.activeLine(at: 4)?.id == first.id)
        #expect(lyrics.activeLine(at: 7.99)?.id == first.id)
        #expect(lyrics.activeLine(at: 8)?.id == second.id)
        #expect(lyrics.activeLine(at: 999)?.id == third.id)
    }

    @Test("Timestamp validation allows missing stanza times and reports exact rows")
    func validation() {
        let lyrics = document(
            texts: ["Negative", "", "Late", "Backwards"],
            times: [-1, nil, 13, 8]
        )
        let issues = lyrics.validationIssues(trackDuration: 10)

        #expect(issues.map(\.lineID) == [
            lyrics.lines[0].id,
            lyrics.lines[2].id,
            lyrics.lines[3].id,
        ])
        #expect(issues.map(\.kind) == [
            .negative,
            .exceedsTrackDuration,
            .decreasing,
        ])
    }

    @Test("Non-finite timestamps are rejected")
    func nonFiniteValidation() {
        let lyrics = document(
            texts: ["NaN", "Infinity"],
            times: [.nan, .infinity]
        )

        #expect(lyrics.validationIssues(trackDuration: 100).map(\.kind) == [
            .nonFinite,
            .nonFinite,
        ])
    }

    @Test("Plain text creates one line per source line and preserves stanzas")
    func plainText() {
        let lines = LyricDocument.lines(fromPlainText: "First\n\nThird")

        #expect(lines.map(\.text) == ["First", "", "Third"])
        #expect(lines.allSatisfy { $0.startTime == nil })
    }

    @Test("Line-level LRC parses metadata, timestamps, and stanza rows")
    func lrcParsing() throws {
        let source = """
        [ar:North Assembly]
        [00:04.20]First line

        [00:08.005]Second line
        """

        let document = try LineLevelLRC.parse(source, trackID: 7)

        #expect(document.lines.map(\.text) == ["First line", "", "Second line"])
        #expect(document.lines[0].startTime == 4.2)
        #expect(document.lines[1].startTime == nil)
        #expect(document.lines[2].startTime == 8.005)
    }

    @Test("Malformed LRC fails without returning partial content")
    func malformedLRC() {
        #expect(throws: LineLevelLRC.Error.self) {
            try LineLevelLRC.parse(
                "[00:04.20]Valid\n[broken]Nope",
                trackID: 8
            )
        }
    }

    @Test("LRC generation is line-level and round trips synchronized lyrics")
    func lrcGeneration() throws {
        let original = document(
            trackID: 9,
            texts: ["First", "", "Second"],
            times: [4.2, nil, 68.005]
        )

        let output = try LineLevelLRC.generate(original)
        let parsed = try LineLevelLRC.parse(output, trackID: 9)

        #expect(output == "[00:04.200]First\n\n[01:08.005]Second")
        #expect(parsed.lines.map(\.text) == original.lines.map(\.text))
        #expect(parsed.lines.map(\.startTime) == original.lines.map(\.startTime))
    }

    @Test("Incomplete lyrics cannot be exported as synchronized LRC")
    func incompleteGeneration() {
        let lyrics = document(
            texts: ["First", "Second"],
            times: [1, nil]
        )

        #expect(throws: LineLevelLRC.Error.self) {
            try LineLevelLRC.generate(lyrics)
        }
    }

    @Test("Timestamp formatting is deterministic")
    func formatting() {
        #expect(LyricTimestampFormatter.display(68.005) == "1:08.005")
        #expect(LyricTimestampFormatter.lrc(68.005) == "01:08.005")
    }

    private func document(
        trackID: TrackPreview.ID = 1,
        texts: [String],
        times: [TimeInterval?]
    ) -> LyricDocument {
        LyricDocument(
            trackID: trackID,
            lines: zip(texts, times).map { text, time in
                LyricLine(text: text, startTime: time)
            }
        )
    }
}
