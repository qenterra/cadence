@testable import Cadence
import Testing

@MainActor
struct TagSelectionSummaryTests {
    @Test("Track summaries distinguish direct, mixed, inherited, and excluded sources")
    func trackSummaries() throws {
        let model = CadenceAppModel.preview()

        model.updateTagEditingSelection(.replace, target: .track(1))
        model.updateTagEditingSelection(.toggle, target: .track(2))

        let sad = try #require(
            model.tagSelectionSummaries.first { $0.tag.id == "mood/sad" }
        )
        let ambient = try #require(
            model.tagSelectionSummaries.first { $0.tag.id == "genre/ambient" }
        )

        #expect(sad.state == .mixedDirect)
        #expect(sad.directCount == 1)
        #expect(sad.absentCount == 1)
        #expect(ambient.state == .inherited)
        #expect(ambient.inheritedCount == 2)

        model.updateTagEditingSelection(.replace, target: .track(1))
        model.updateTagEditingSelection(.toggle, target: .track(9))
        let night = try #require(
            model.tagSelectionSummaries.first { $0.tag.id == "context/night" }
        )

        #expect(night.state == .mixedSource)
        #expect(night.inheritedCount == 1)
        #expect(night.excludedCount == 1)
    }

    @Test("Album summaries contain direct and mixed states without inheritance")
    func albumSummaries() throws {
        let model = CadenceAppModel.preview()
        let signalsID = "North Assembly\u{1F}Signals After Dark"
        let midnightID = "North Assembly\u{1F}Midnight Static"
        let transientID = "North Assembly\u{1F}Transient Lines"

        model.tagResultScope = .albums
        model.updateTagEditingSelection(.replace, target: .album(signalsID))
        model.updateTagEditingSelection(.toggle, target: .album(midnightID))

        let night = try #require(
            model.tagSelectionSummaries.first { $0.tag.id == "context/night" }
        )
        #expect(night.state == .allDirect)
        #expect(night.directCount == 2)
        #expect(night.inheritedCount == 0)

        model.updateTagEditingSelection(.toggle, target: .album(transientID))
        let mixedNight = try #require(
            model.tagSelectionSummaries.first { $0.tag.id == "context/night" }
        )
        #expect(mixedNight.state == .mixedDirect)
        #expect(mixedNight.directCount == 2)
        #expect(mixedNight.absentCount == 1)
    }

    @Test("Empty and stale selections produce no summaries")
    func emptySelection() {
        let model = CadenceAppModel.preview()

        #expect(model.tagSelectionSummaries.isEmpty)

        model.updateTagEditingSelection(.replace, target: .track(999))
        model.pruneTagEditingSelection()

        #expect(model.tagEditingSelection.isEmpty)
        #expect(model.tagSelectionSummaries.isEmpty)
    }
}
