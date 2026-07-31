@testable import Cadence
import Foundation
import Testing

@MainActor
struct SmartCollectionAppModelTests {
    @Test("Injected collections select deterministically and derive live counts")
    func initialSelection() {
        let first = collection(
            id: smartCollectionTestID(200),
            name: "North",
            condition: artistCondition("North Assembly")
        )
        let second = collection(
            id: smartCollectionTestID(201),
            name: "Mara",
            condition: artistCondition("Mara Vale")
        )
        let model = CadenceAppModel.testFixture(smartCollections: [first, second])

        #expect(model.selectedSmartCollectionID == first.id)
        #expect(model.smartCollectionDraft == nil)
        #expect(
            model.selectedSmartCollectionCanonicalTracks.allSatisfy {
                $0.artist == "North Assembly"
            }
        )
        #expect(model.smartCollectionMatchCount(for: second) == 2)
    }

    @Test("A new draft remains transient until valid Save")
    func createAndSave() throws {
        let model = CadenceAppModel.testFixture(smartCollections: [])
        let draftID = smartCollectionTestID(210)
        let rootID = smartCollectionTestID(211)

        model.requestNewSmartCollection(draftID: draftID, rootID: rootID)

        #expect(model.smartCollections.isEmpty)
        #expect(model.smartCollectionDraft?.id == draftID)
        #expect(model.smartCollectionListItems.map(\.id) == [draftID])
        #expect(model.smartCollectionListItems.first?.isTransient == true)
        model.renameSmartCollectionDraft("All Tracks")
        let saved = model.saveSmartCollectionDraft(
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let collection = try #require(model.smartCollections.first)

        #expect(saved)
        #expect(collection.id == draftID)
        #expect(collection.name == "All Tracks")
        #expect(collection.modifiedAt == Date(timeIntervalSince1970: 100))
        #expect(model.smartCollectionDraft?.sourceID == collection.id)
        #expect(!model.isSmartCollectionDraftDirty)
    }

    @Test("Valid edits update live results and invalid edits preserve the last valid IDs")
    func liveAndInvalidPreview() throws {
        let model = CadenceAppModel.testFixture(smartCollections: [])
        model.requestNewSmartCollection(
            draftID: smartCollectionTestID(220),
            rootID: smartCollectionTestID(221)
        )
        model.renameSmartCollectionDraft("North")
        let rootID = try #require(model.smartCollectionDraft?.rule.id)
        let conditionID = smartCollectionTestID(222)
        model.addSmartCollectionCondition(
            artistCondition("North Assembly", id: conditionID),
            to: rootID
        )
        let validIDs = model.smartCollectionLiveTracks.map(\.id)

        #expect(!validIDs.isEmpty)
        #expect(model.smartCollectionLiveTracks.allSatisfy { $0.artist == "North Assembly" })

        model.updateSmartCollectionValue(.text(""), conditionID: conditionID)

        #expect(!model.smartCollectionValidation.isValid)
        #expect(model.smartCollectionLiveTracks.map(\.id) == validIDs)
        #expect(!model.canSaveSmartCollectionDraft)
    }

    @Test("Dirty switching supports Cancel, Discard, and Save")
    func guardedSwitching() throws {
        let first = collection(
            id: smartCollectionTestID(230),
            name: "First",
            condition: artistCondition("North Assembly")
        )
        let second = collection(
            id: smartCollectionTestID(231),
            name: "Second",
            condition: artistCondition("Mara Vale")
        )
        let model = CadenceAppModel.testFixture(smartCollections: [first, second])
        model.requestEditSelectedSmartCollection()
        model.renameSmartCollectionDraft("Changed")

        model.requestSelectSmartCollection(second.id)
        #expect(
            model.pendingSmartCollectionTransition == .collection(second.id)
        )

        model.resolvePendingSmartCollectionTransition(.cancel)
        #expect(model.selectedSmartCollectionID == first.id)
        #expect(model.smartCollectionDraft?.name == "Changed")

        model.requestSelectSmartCollection(second.id)
        model.resolvePendingSmartCollectionTransition(.discard)
        #expect(model.selectedSmartCollectionID == second.id)
        #expect(model.smartCollectionDraft?.name == second.name)

        model.renameSmartCollectionDraft("Saved Second")
        model.requestSelectSmartCollection(first.id)
        let resolved = model.resolvePendingSmartCollectionTransition(
            .save,
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let savedSecond = try #require(
            model.smartCollections.first { $0.id == second.id }
        )

        #expect(resolved)
        #expect(savedSecond.name == "Saved Second")
        #expect(model.selectedSmartCollectionID == first.id)
    }

    @Test("Revert and deletion restore predictable saved state")
    func revertAndDelete() {
        let first = collection(
            id: smartCollectionTestID(240),
            name: "First",
            condition: artistCondition("North Assembly")
        )
        let second = collection(
            id: smartCollectionTestID(241),
            name: "Second",
            condition: artistCondition("Mara Vale")
        )
        let model = CadenceAppModel.testFixture(smartCollections: [first, second])
        model.requestEditSelectedSmartCollection()
        model.renameSmartCollectionDraft("Changed")

        let reverted = model.revertSmartCollectionDraft()
        #expect(reverted)
        #expect(model.smartCollectionDraft?.name == first.name)

        model.requestDeleteSmartCollection(first.id)
        #expect(model.pendingSmartCollectionDeletionID == first.id)
        let deleted = model.confirmDeleteSmartCollection()

        #expect(deleted)
        #expect(model.smartCollections.map(\.id) == [second.id])
        #expect(model.selectedSmartCollectionID == second.id)
        #expect(model.smartCollectionDraft == nil)
        #expect(model.smartCollectionsPresentationMode == .listening)
    }

    @Test("Saved counts use current favorite state and result selection stays shared")
    func liveContextAndTrackSelection() throws {
        let favorite = collection(
            id: smartCollectionTestID(250),
            name: "Favorites",
            condition: SmartCollectionRuleCondition(
                field: .favorite,
                operator: .is,
                value: .boolean(true)
            )
        )
        let model = CadenceAppModel.testFixture(smartCollections: [favorite])
        let originalCount = model.smartCollectionMatchCount(for: favorite)
        let track = try #require(model.tracks.first)

        model.toggleFavorite(track)
        let updatedCount = model.smartCollectionMatchCount(for: favorite)
        model.selectTrack(track)

        #expect(updatedCount == originalCount - 1)
        #expect(model.selectedTrackID == track.id)

        model.play(track)
        #expect(model.currentTrackID == track.id)
        #expect(model.selectedTrackID == track.id)
    }
}

private extension SmartCollectionAppModelTests {
    func collection(
        id: UUID,
        name: String,
        condition: SmartCollectionRuleCondition
    ) -> SmartCollectionPreview {
        SmartCollectionPreview(
            id: id,
            name: name,
            rule: SmartCollectionRuleGroup(
                id: smartCollectionTestID(300),
                combinator: .all,
                children: [.condition(condition)]
            ),
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func artistCondition(
        _ artist: String,
        id: UUID = UUID()
    ) -> SmartCollectionRuleCondition {
        SmartCollectionRuleCondition(
            id: id,
            field: .artist,
            operator: .is,
            value: .text(artist)
        )
    }
}
