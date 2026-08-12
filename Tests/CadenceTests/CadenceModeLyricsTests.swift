@testable import Cadence
import Foundation
import Testing

struct CadenceModeLyricsTests {
    @MainActor
    @Test("Cadence lyric rows seek to their synchronized timestamp")
    func lyricRowSeekTarget() {
        let timed = LyricLine(text: "timed", startTime: 42.5)
        let untimed = LyricLine(text: "untimed", startTime: nil)

        #expect(CadenceModeLyricInteraction.seekTime(for: timed) == 42.5)
        #expect(CadenceModeLyricInteraction.seekTime(for: untimed) == nil)
        #expect(CadenceModeLyricsEdgeFade.topOpaqueLocation > 0)
        #expect(CadenceModeLyricsEdgeFade.bottomFadeLocation < 1)
    }

    @Test("The active lyric stays in the center of five stable slots")
    func activeLineIsCentered() {
        let document = makeDocument(
            ["one", "two", "three", "four", "five", "six"],
            startTimes: [0, 2, 4, 6, 8, 10]
        )

        let projection = CadenceModeLyricProjection.make(
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

        let beginning = CadenceModeLyricProjection.make(
            document: document,
            presentationTime: 0.5
        )
        let end = CadenceModeLyricProjection.make(
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

    @Test("Blank document rows never consume a Cadence Mode slot")
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

        let projection = CadenceModeLyricProjection.make(
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

        let missingProjection = CadenceModeLyricProjection.make(
            document: nil,
            presentationTime: 3
        )
        let unsynchronizedProjection = CadenceModeLyricProjection.make(
            document: unsynchronized,
            presentationTime: 3
        )
        let partialProjection = CadenceModeLyricProjection.make(
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

        let projection = CadenceModeLyricProjection.make(
            document: document,
            presentationTime: 2
        )

        #expect(projection.activeLineID == nil)
        #expect(projection.slots.map { $0?.text } == [
            nil, nil, "one", "two", "three",
        ])
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
