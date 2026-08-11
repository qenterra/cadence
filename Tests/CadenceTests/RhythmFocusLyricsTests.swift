@testable import Cadence
import Foundation
import Testing

struct RhythmFocusLyricsTests {
    @Test("The active lyric stays in the center of five stable slots")
    func activeLineIsCentered() {
        let document = makeDocument(
            ["one", "two", "three", "four", "five", "six"],
            startTimes: [0, 2, 4, 6, 8, 10]
        )

        let projection = RhythmFocusLyricProjection.make(
            document: document,
            presentationTime: 6.5
        )

        #expect(projection.status == .synchronized)
        #expect(projection.slots.map { $0?.text } == [
            "two", "three", "four", "five", "six",
        ])
        #expect(projection.slots[2]?.id == projection.activeLineID)
    }

    @Test("Document edges use empty slots instead of moving the active row")
    func documentEdgesKeepStableSlots() {
        let document = makeDocument(
            ["one", "two", "three"],
            startTimes: [0, 2, 4]
        )

        let beginning = RhythmFocusLyricProjection.make(
            document: document,
            presentationTime: 0.5
        )
        let end = RhythmFocusLyricProjection.make(
            document: document,
            presentationTime: 8
        )

        #expect(beginning.slots.map { $0?.text } == [
            nil, nil, "one", "two", "three",
        ])
        #expect(end.slots.map { $0?.text } == [
            "one", "two", "three", nil, nil,
        ])
        #expect(beginning.slots[2]?.id == beginning.activeLineID)
        #expect(end.slots[2]?.id == end.activeLineID)
    }

    @Test("Blank document rows never consume a focus slot")
    func blankRowsAreSkipped() {
        let document = LyricDocument(
            trackID: UUID(),
            lines: [
                LyricLine(text: "one", startTime: 0),
                LyricLine(text: "", startTime: 1),
                LyricLine(text: "two", startTime: 2),
                LyricLine(text: "   ", startTime: 3),
                LyricLine(text: "three", startTime: 4),
            ]
        )

        let projection = RhythmFocusLyricProjection.make(
            document: document,
            presentationTime: 2.5
        )

        #expect(projection.slots.map { $0?.text } == [
            nil, "one", "two", "three", nil,
        ])
    }

    @Test("Unavailable timing never invents an active lyric")
    func unavailableTimingHasNoActiveLine() {
        let unsynchronized = makeDocument(
            ["one", "two"],
            startTimes: [nil, nil]
        )
        let partial = makeDocument(
            ["one", "two"],
            startTimes: [0, nil]
        )

        let missingProjection = RhythmFocusLyricProjection.make(
            document: nil,
            presentationTime: 3
        )
        let unsynchronizedProjection = RhythmFocusLyricProjection.make(
            document: unsynchronized,
            presentationTime: 3
        )
        let partialProjection = RhythmFocusLyricProjection.make(
            document: partial,
            presentationTime: 3
        )

        #expect(missingProjection.status == .missing)
        #expect(unsynchronizedProjection.status == .unsynchronized)
        #expect(partialProjection.status == .partiallySynchronized)
        #expect(missingProjection.activeLineID == nil)
        #expect(unsynchronizedProjection.slots.allSatisfy { $0 == nil })
        #expect(partialProjection.slots.allSatisfy { $0 == nil })
    }

    @Test("Before the first timestamp the first lyric is upcoming, not active")
    func firstLineCanBeUpcoming() {
        let document = makeDocument(
            ["one", "two", "three"],
            startTimes: [5, 7, 9]
        )

        let projection = RhythmFocusLyricProjection.make(
            document: document,
            presentationTime: 2
        )

        #expect(projection.activeLineID == nil)
        #expect(projection.slots.map { $0?.text } == [
            nil, nil, "one", "two", "three",
        ])
    }

    @Test("Focus shimmer uses the production lyric duration contract")
    func focusUsesProductionLineDuration() throws {
        let document = makeDocument(
            ["one", "two", "three"],
            startTimes: [0, 2, 2.4]
        )
        let first = try #require(document.lines.first)
        let second = document.lines[1]
        let last = try #require(document.lines.last)

        #expect(
            ProductionLyricTiming.animationDuration(
                for: first.id,
                in: document
            ) == 2
        )
        #expect(
            ProductionLyricTiming.animationDuration(
                for: second.id,
                in: document
            ) == 1.2
        )
        #expect(
            ProductionLyricTiming.animationDuration(
                for: last.id,
                in: document
            ) == 4
        )
    }

    private func makeDocument(
        _ texts: [String],
        startTimes: [TimeInterval?]
    ) -> LyricDocument {
        LyricDocument(
            trackID: UUID(),
            lines: zip(texts, startTimes).map {
                LyricLine(text: $0, startTime: $1)
            }
        )
    }
}
