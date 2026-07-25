@testable import Cadence
import Foundation
import Testing

@MainActor
struct SmartCollectionListeningLifecycleTests {
    @Test("Initial state selects a saved collection in listening mode without a draft")
    func initialListeningState() {
        let first = collection(id: testID(1), name: "First")
        let second = collection(id: testID(2), name: "Second")
        let model = CadenceAppModel(smartCollections: [first, second])

        #expect(model.smartCollectionsPresentationMode == .listening)
        #expect(model.selectedSmartCollectionID == first.id)
        #expect(model.smartCollectionDraft == nil)

        model.requestSelectSmartCollection(second.id)
        #expect(model.selectedSmartCollectionID == second.id)
        #expect(model.smartCollectionDraft == nil)
    }

    @Test("Edit Rules creates an isolated draft and clean Done returns to listening")
    func cleanEditing() {
        let saved = collection(id: testID(10), name: "Saved")
        let model = CadenceAppModel(smartCollections: [saved])

        #expect(model.requestEditSelectedSmartCollection())
        #expect(model.smartCollectionsPresentationMode == .editing)
        #expect(model.smartCollectionDraft?.sourceID == saved.id)
        #expect(!model.isSmartCollectionDraftDirty)

        model.requestFinishSmartCollectionEditing()

        #expect(model.smartCollectionsPresentationMode == .listening)
        #expect(model.smartCollectionDraft == nil)
        #expect(model.selectedSmartCollectionID == saved.id)
    }

    @Test("Dirty Done supports Cancel, Discard, and Save")
    func guardedDone() {
        let saved = collection(id: testID(20), name: "Saved")
        let model = CadenceAppModel(smartCollections: [saved])
        model.requestEditSelectedSmartCollection()
        model.renameSmartCollectionDraft("Changed")

        model.requestFinishSmartCollectionEditing()
        #expect(model.pendingSmartCollectionTransition == .listening)

        model.resolvePendingSmartCollectionTransition(.cancel)
        #expect(model.smartCollectionsPresentationMode == .editing)
        #expect(model.smartCollectionDraft?.name == "Changed")

        model.requestFinishSmartCollectionEditing()
        model.resolvePendingSmartCollectionTransition(.discard)
        #expect(model.smartCollectionsPresentationMode == .listening)
        #expect(model.selectedSmartCollection?.name == "Saved")

        model.requestEditSelectedSmartCollection()
        model.renameSmartCollectionDraft("Saved Change")
        model.requestFinishSmartCollectionEditing()
        let resolved = model.resolvePendingSmartCollectionTransition(
            .save,
            modifiedAt: Date(timeIntervalSince1970: 99)
        )

        #expect(resolved)
        #expect(model.smartCollectionsPresentationMode == .listening)
        #expect(model.selectedSmartCollection?.name == "Saved Change")
        #expect(model.smartCollectionDraft == nil)
    }

    @Test("A new transient draft opens editing and Discard restores prior selection")
    func newDraft() {
        let saved = collection(id: testID(30), name: "Saved")
        let model = CadenceAppModel(smartCollections: [saved])
        let draftID = testID(31)

        model.requestNewSmartCollection(
            draftID: draftID,
            rootID: testID(32)
        )

        #expect(model.smartCollectionsPresentationMode == .editing)
        #expect(model.selectedSmartCollectionID == nil)
        #expect(model.smartCollectionDraft?.id == draftID)
        #expect(model.smartCollectionListItems.last?.isTransient == true)

        model.requestFinishSmartCollectionEditing()
        #expect(model.pendingSmartCollectionTransition == .listening)
        model.resolvePendingSmartCollectionTransition(.discard)

        #expect(model.smartCollectionsPresentationMode == .listening)
        #expect(model.selectedSmartCollectionID == saved.id)
        #expect(model.smartCollectionDraft == nil)
    }

    @Test("Collection switches stay in editing and guard dirty drafts")
    func editingSwitch() {
        let first = collection(id: testID(40), name: "First")
        let second = collection(id: testID(41), name: "Second")
        let model = CadenceAppModel(smartCollections: [first, second])
        model.requestEditSelectedSmartCollection()

        model.requestSelectSmartCollection(second.id)
        #expect(model.smartCollectionsPresentationMode == .editing)
        #expect(model.selectedSmartCollectionID == second.id)
        #expect(model.smartCollectionDraft?.sourceID == second.id)

        model.renameSmartCollectionDraft("Dirty")
        model.requestSelectSmartCollection(first.id)
        #expect(
            model.pendingSmartCollectionTransition
                == .collection(first.id)
        )

        model.resolvePendingSmartCollectionTransition(.discard)
        #expect(model.smartCollectionsPresentationMode == .editing)
        #expect(model.selectedSmartCollectionID == first.id)
        #expect(model.smartCollectionDraft?.sourceID == first.id)
    }

    @Test("Dirty destination navigation resolves before leaving Smart Collections")
    func guardedNavigation() {
        let saved = collection(id: testID(50), name: "Saved")
        let model = CadenceAppModel(smartCollections: [saved])
        model.selectedDestination = .smartCollections
        model.requestEditSelectedSmartCollection()
        model.renameSmartCollectionDraft("Dirty")

        model.requestNavigationDestination(.library)
        #expect(model.selectedDestination == .smartCollections)
        #expect(
            model.pendingSmartCollectionTransition
                == .destination(.library)
        )

        model.resolvePendingSmartCollectionTransition(.cancel)
        #expect(model.selectedDestination == .smartCollections)
        #expect(model.smartCollectionsPresentationMode == .editing)

        model.requestNavigationDestination(.library)
        model.resolvePendingSmartCollectionTransition(.discard)
        #expect(model.selectedDestination == .library)
        #expect(model.smartCollectionsPresentationMode == .listening)
        #expect(model.smartCollectionDraft == nil)

        model.requestNavigationDestination(.smartCollections)
        #expect(model.selectedDestination == .smartCollections)
        #expect(model.smartCollectionsPresentationMode == .listening)
    }

    @Test("Rename enters editing and emits a one-shot focus request")
    func rename() {
        let saved = collection(id: testID(60), name: "Saved")
        let model = CadenceAppModel(smartCollections: [saved])

        model.requestRenameSmartCollection(saved.id)
        let request = model.smartCollectionNameFocusRequest

        #expect(model.smartCollectionsPresentationMode == .editing)
        #expect(model.smartCollectionDraft?.sourceID == saved.id)
        #expect(request != nil)

        model.consumeSmartCollectionNameFocusRequest(request)
        #expect(model.smartCollectionNameFocusRequest == nil)
    }

    @Test("Deleting the selected collection returns to listening on its neighbor")
    func deletion() {
        let first = collection(id: testID(70), name: "First")
        let second = collection(id: testID(71), name: "Second")
        let model = CadenceAppModel(smartCollections: [first, second])
        model.requestEditSelectedSmartCollection()

        model.requestDeleteSmartCollection(first.id)
        model.confirmDeleteSmartCollection()

        #expect(model.smartCollectionsPresentationMode == .listening)
        #expect(model.selectedSmartCollectionID == second.id)
        #expect(model.smartCollectionDraft == nil)
    }
}

private extension SmartCollectionListeningLifecycleTests {
    func collection(
        id: UUID,
        name: String
    ) -> SmartCollectionPreview {
        SmartCollectionPreview(
            id: id,
            name: name,
            rule: SmartCollectionRuleGroup(
                id: testID(UInt32(id.uuid.15) + 100),
                combinator: .all,
                children: []
            ),
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testID(_ value: UInt32) -> UUID {
        UUID(
            uuidString: String(
                format: "CA200000-0000-0000-0000-%012X",
                value
            )
        ) ?? UUID()
    }
}
