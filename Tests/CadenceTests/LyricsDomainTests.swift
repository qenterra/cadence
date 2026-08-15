@testable import Cadence
import Foundation
import Testing

struct LyricsDomainTests {
    @Test("A lyric line can be replaced without changing timing or identity")
    func replacingLineText() throws {
        let line = LyricLine(text: "Before", startTime: 12.5)
        let document = LyricDocument(trackID: UUID(), lines: [line])

        let updated = try #require(
            document.replacingText(
                for: line.id,
                with: "  After  "
            )
        )

        #expect(updated.lines[0].id == line.id)
        #expect(updated.lines[0].startTime == 12.5)
        #expect(updated.lines[0].text == "After")
        #expect(document.lines[0].text == "Before")
        #expect(document.replacingText(for: UUID(), with: "Missing") == nil)
    }

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

    @Test("Compiled lyric timeline keeps exact timestamp boundaries")
    func compiledTimelineLookup() {
        let lyrics = document(
            texts: ["First", "Second", "Third"],
            times: [4, 8, 12]
        )
        let timeline = SynchronizedLyricTimeline(document: lyrics)

        #expect(timeline.activeLineID(at: 3.99) == nil)
        #expect(timeline.activeLineID(at: 4) == lyrics.lines[0].id)
        #expect(timeline.activeLineID(at: 11.99) == lyrics.lines[1].id)
        #expect(timeline.activeLineID(at: 12) == lyrics.lines[2].id)
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
        #expect(document.metadataLines == ["[ar:North Assembly]"])
    }

    @Test("Malformed timestamp fails without returning partial content")
    func malformedLRC() {
        #expect(throws: LineLevelLRC.Error.self) {
            try LineLevelLRC.parse(
                "[00:04.20]Valid\n[00:99.000]Nope",
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

        #expect(output == "[00:04.200]First\n\n[01:08.005]Second\n")
        #expect(parsed.lines.map(\.text) == original.lines.map(\.text))
        #expect(parsed.lines.map(\.startTime) == original.lines.map(\.startTime))
    }

    @Test("Partial lyrics round trip timed and untimed lines")
    func partialGeneration() throws {
        let lyrics = document(
            texts: ["First", "Second"],
            times: [1, nil]
        )

        let output = try LineLevelLRC.generate(lyrics)
        let parsed = try LineLevelLRC.parse(output, trackID: 1)

        #expect(output == "[00:01.000]First\nSecond\n")
        #expect(parsed.timingStatus == .partiallySynchronized)
        #expect(parsed.lines.map(\.text) == ["First", "Second"])
        #expect(parsed.lines.map(\.startTime) == [1, nil])
    }

    @Test("Metadata and repeated timestamps survive parsing and generation")
    func metadataAndRepeatedTimestamps() throws {
        let source = """
        [ar:North Assembly]
        [al:Signals]
        [00:01.00][00:03.500]Echo
        Untimed
        """

        let document = try LineLevelLRC.parse(source, trackID: 1)
        let output = try LineLevelLRC.generate(document)

        #expect(document.metadataLines == [
            "[ar:North Assembly]",
            "[al:Signals]",
        ])
        #expect(document.lines.map(\.text) == ["Echo", "Echo", "Untimed"])
        #expect(document.lines.map(\.startTime) == [1, 3.5, nil])
        #expect(
            output
                == """
                [ar:North Assembly]
                [al:Signals]
                [00:01.000]Echo
                [00:03.500]Echo
                Untimed

                """
        )
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
