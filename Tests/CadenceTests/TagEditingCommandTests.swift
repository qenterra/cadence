@testable import Cadence
import Foundation
import Testing

@MainActor
struct TagEditingCommandTests {
    @Test("Bulk assignment is one undoable and redoable operation")
    func bulkAssignmentUndo() {
        let model = CadenceAppModel()
        let undoManager = UndoManager()
        let targets: [TagAssignmentTarget] = [.track(1), .track(2)]

        #expect(
            model.performTagEdit(
                .assign(tagID: "roadtrip", targets: targets),
                undoManager: undoManager
            )
        )
        #expect(undoManager.undoActionName == "Assign Tag to 2 Tracks")
        #expect(targets.allSatisfy { target in
            model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "roadtrip", target: target)
            )
        })

        undoManager.undo()
        #expect(targets.allSatisfy { target in
            !model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "roadtrip", target: target)
            )
        })

        undoManager.redo()
        #expect(targets.allSatisfy { target in
            model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "roadtrip", target: target)
            )
        })
    }

    @Test("Album batches use the same semantic command path")
    func albumBatchAssignment() {
        let model = CadenceAppModel()
        let targets = model.albums.prefix(2).map {
            TagAssignmentTarget.album($0.id)
        }
        let undoManager = UndoManager()

        #expect(
            model.performTagEdit(
                .assign(tagID: "roadtrip", targets: targets),
                undoManager: undoManager
            )
        )
        #expect(targets.allSatisfy { target in
            model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "roadtrip", target: target)
            )
        })

        undoManager.undo()
        #expect(targets.allSatisfy { target in
            !model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "roadtrip", target: target)
            )
        })
        undoManager.redo()
        #expect(targets.allSatisfy { target in
            model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "roadtrip", target: target)
            )
        })
    }

    @Test("Removing a direct tag reveals an inherited album tag")
    func removeDirectRevealsInheritance() throws {
        let base = CadenceAppModel()
        var assignments = base.tagAssignments
        assignments.insert(
            TagAssignmentPreview(tagID: "genre/ambient", target: .track(1))
        )
        let model = CadenceAppModel(tagAssignments: assignments)

        #expect(
            model.performTagEdit(
                .removeDirect(tagID: "genre/ambient", targets: [.track(1)])
            )
        )

        let track = try #require(model.tracks.first { $0.id == 1 })
        #expect(model.tagMatchSource(for: track, tagID: "genre/ambient") == .inherited)
    }

    @Test("Exclude and restore mutate only applicable inherited tracks")
    func excludeAndRestore() throws {
        let model = CadenceAppModel()
        let track = try #require(model.tracks.first { $0.id == 1 })
        let undoManager = UndoManager()

        #expect(
            model.performTagEdit(
                .excludeInherited(tagID: "context/night", trackIDs: [1, 31]),
                undoManager: undoManager
            )
        )
        #expect(model.tagMatchSource(for: track, tagID: "context/night") == nil)
        #expect(
            model.tagExclusions.contains(
                TagExclusionPreview(tagID: "context/night", trackID: 1)
            )
        )
        #expect(
            !model.tagExclusions.contains(
                TagExclusionPreview(tagID: "context/night", trackID: 31)
            )
        )

        undoManager.undo()
        #expect(model.tagMatchSource(for: track, tagID: "context/night") == .inherited)
        undoManager.redo()
        #expect(model.tagMatchSource(for: track, tagID: "context/night") == nil)

        #expect(
            model.performTagEdit(
                .restoreInheritance(tagID: "context/night", trackIDs: [1]),
                undoManager: undoManager
            )
        )
        #expect(model.tagMatchSource(for: track, tagID: "context/night") == .inherited)

        undoManager.undo()
        #expect(model.tagMatchSource(for: track, tagID: "context/night") == nil)
        undoManager.redo()
        #expect(model.tagMatchSource(for: track, tagID: "context/night") == .inherited)
    }

    @Test("Create and assign normalizes paths and does not duplicate existing tags")
    func createAndAssign() {
        let model = CadenceAppModel()
        let originalTagCount = model.tags.count

        #expect(
            model.performTagEdit(
                .createAndAssign(path: " Mood / Nostalgic ", targets: [.track(1)])
            )
        )
        #expect(model.tags.contains { $0.id == "mood/nostalgic" })
        #expect(
            model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "mood/nostalgic", target: .track(1))
            )
        )

        #expect(
            model.performTagEdit(
                .createAndAssign(path: "mood/nostalgic", targets: [.track(2)])
            )
        )
        #expect(model.tags.count == originalTagCount + 1)
        #expect(
            !model.performTagEdit(
                .createAndAssign(path: "genre//broken", targets: [.track(1)])
            )
        )
    }

    @Test("Create and assign undo removes an unreferenced new tag")
    func createAndAssignUndo() {
        let model = CadenceAppModel()
        let undoManager = UndoManager()

        #expect(
            model.performTagEdit(
                .createAndAssign(path: "memory/summer", targets: [.track(1)]),
                undoManager: undoManager
            )
        )
        #expect(model.tags.contains { $0.id == "memory/summer" })

        undoManager.undo()

        #expect(!model.tags.contains { $0.id == "memory/summer" })
        #expect(
            !model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "memory/summer", target: .track(1))
            )
        )
    }

    @Test("Removing the active result prunes selection and Undo conditionally restores it")
    func activeResultSelectionRestoration() throws {
        let model = CadenceAppModel()
        let sad = try #require(model.tags.first { $0.id == "mood/sad" })
        let undoManager = UndoManager()

        model.selectTag(sad)
        model.openTagInspector(for: .track(1))
        #expect(model.tagEditingSelection.targets == [.track(1)])
        #expect(model.isTagInspectorPresented)

        #expect(
            model.performTagEdit(
                .removeDirect(tagID: sad.id, targets: [.track(1)]),
                undoManager: undoManager
            )
        )
        #expect(model.tagEditingSelection.isEmpty)
        #expect(!model.isTagInspectorPresented)

        undoManager.undo()
        #expect(model.tagEditingSelection.targets == [.track(1)])
        #expect(model.isTagInspectorPresented)

        undoManager.redo()
        let ambient = try #require(model.tags.first { $0.id == "genre/ambient" })
        model.selectTag(ambient)
        undoManager.undo()

        #expect(
            model.tagAssignments.contains(
                TagAssignmentPreview(tagID: sad.id, target: .track(1))
            )
        )
        #expect(model.tagEditingSelection.isEmpty)
        #expect(!model.isTagInspectorPresented)
    }

    @Test("Changing tag group, tag, or scope clears batch selection")
    func browsingContextClearsSelection() throws {
        let model = CadenceAppModel()

        model.openTagInspector(for: .track(1))
        model.updateTagEditingSelection(.toggle, target: .track(1))
        #expect(model.tagEditingSelection.isEmpty)
        #expect(!model.isTagInspectorPresented)

        model.openTagInspector(for: .track(999))
        #expect(model.tagEditingSelection.isEmpty)

        model.openTagInspector(for: .track(1))
        model.selectTagResultScope(.albums)
        #expect(model.tagEditingSelection.isEmpty)
        #expect(!model.isTagInspectorPresented)

        let ambient = try #require(model.tags.first { $0.id == "genre/ambient" })
        model.selectTagResultScope(.tracks)
        model.openTagInspector(for: .track(1))
        model.selectTag(ambient)
        #expect(model.tagEditingSelection.targets == [.track(1)])

        let sad = try #require(model.tags.first { $0.id == "mood/sad" })
        model.selectTag(sad)
        #expect(model.tagEditingSelection.isEmpty)
        #expect(!model.isTagInspectorPresented)

        model.openTagInspector(for: .track(1))
        let standalone = try #require(
            model.tagGroups.first { $0.id == .standalone }
        )
        model.selectTagGroup(standalone)
        #expect(model.tagEditingSelection.isEmpty)
        #expect(!model.isTagInspectorPresented)
    }
}
