@testable import Cadence
import Foundation
import Testing

@MainActor
struct TagSuggestionEngineTests {
    @Test("Track album peers produce the strongest local evidence")
    func trackAlbumPeers() throws {
        let model = CadenceAppModel.preview(
            tagAssignments: assignments(
                adding: "mood/calm",
                toTracks: [2, 3, 4, 5, 6, 7]
            )
        )
        let suggestion = try #require(
            model.tagSuggestions(for: [.track(1)])
                .first { $0.tag.id == "mood/calm" }
        )

        #expect(suggestion.evidence == .album)
        #expect(suggestion.eligibleTargets == [.track(1)])
        #expect(suggestion.reason == "Used by 6 other tracks on this album")
    }

    @Test("Track artist consistency requires multiple other albums")
    func trackArtistConsistency() throws {
        let model = CadenceAppModel.preview(
            tagAssignments: assignments(
                adding: "roadtrip",
                toTracks: [13, 15, 17]
            )
        )
        let suggestion = try #require(
            model.tagSuggestions(for: [.track(1)])
                .first { $0.tag.id == "roadtrip" }
        )

        #expect(suggestion.evidence == .artist)
        #expect(suggestion.reason == "Used across 3 other albums by this artist")
    }

    @Test("Track co-occurrence uses an effective seed tag")
    func trackCooccurrence() throws {
        let model = CadenceAppModel.preview(
            tagAssignments: assignments(
                adding: "mood/calm",
                toTracks: Array(1 ... 8)
            )
        )
        let suggestion = try #require(
            model.tagSuggestions(for: [.track(31)])
                .first { $0.tag.id == "mood/calm" }
        )

        #expect(suggestion.evidence == .cooccurrence)
        #expect(suggestion.reason == "Often paired with genre/ambient")
    }

    @Test("Album track consensus suggests an album assignment")
    func albumTrackConsensus() throws {
        let albumID = "North Assembly\u{1F}Signals After Dark"
        let model = CadenceAppModel.preview(
            tagAssignments: assignments(
                adding: "mood/sad",
                toTracks: Array(1 ... 8)
            )
        )
        let suggestion = try #require(
            model.tagSuggestions(for: [.album(albumID)])
                .first { $0.tag.id == "mood/sad" }
        )

        #expect(suggestion.evidence == .album)
        #expect(suggestion.reason == "Used by 8 tracks on this album")
    }

    @Test("Album artist consistency uses direct album assignments")
    func albumArtistConsistency() throws {
        let coastalID = "North Assembly\u{1F}Coastal Machines"
        let model = CadenceAppModel.preview()
        let suggestion = try #require(
            model.tagSuggestions(for: [.album(coastalID)])
                .first { $0.tag.id == "context/night" }
        )

        #expect(suggestion.evidence == .artist)
        #expect(suggestion.reason == "Used across 2 other albums by this artist")
    }

    @Test("Suggestions aggregate eligible targets and remain deterministic")
    func aggregationAndOrdering() throws {
        let model = CadenceAppModel.preview(
            tagAssignments: assignments(
                adding: "mood/calm",
                toTracks: [2, 3, 4, 5, 6, 7]
            )
        )
        let targets: [TagAssignmentTarget] = [.track(1), .track(2)]
        let firstPass = model.tagSuggestions(for: targets)
        let assignmentsBeforeRecalculation = model.tagAssignments
        let secondPass = model.tagSuggestions(for: targets)
        let calm = try #require(firstPass.first { $0.tag.id == "mood/calm" })

        #expect(firstPass == secondPass)
        #expect(model.tagAssignments == assignmentsBeforeRecalculation)
        #expect(calm.eligibleTargets == [.track(1)])
        #expect(calm.selectionCount == 2)
    }

    @Test("Excluded and dismissed candidates do not return")
    func exclusionsAndDismissals() {
        let assignments = assignments(
            adding: "mood/calm",
            toTracks: [2, 3, 4, 5, 6, 7]
        )
        let exclusions: Set<TagExclusionPreview> = [
            TagExclusionPreview(tagID: "mood/calm", trackID: 1),
        ]
        let excludedModel = CadenceAppModel.preview(
            tagAssignments: assignments,
            tagExclusions: exclusions
        )
        #expect(
            excludedModel.tagSuggestions(for: [.track(1)])
                .allSatisfy { $0.tag.id != "mood/calm" }
        )

        let dismissedModel = CadenceAppModel.preview(tagAssignments: assignments)
        #expect(
            dismissedModel.performTagEdit(
                .dismissSuggestion(tagID: "mood/calm", targets: [.track(1)])
            )
        )
        #expect(
            dismissedModel.tagSuggestions(for: [.track(1)])
                .allSatisfy { $0.tag.id != "mood/calm" }
        )
    }

    @Test("Accept remains an explicit undoable operation")
    func acceptUndo() throws {
        let model = CadenceAppModel.preview(
            tagAssignments: assignments(
                adding: "mood/calm",
                toTracks: [2, 3, 4, 5, 6, 7]
            )
        )
        let suggestion = try #require(
            model.tagSuggestions(for: [.track(1)])
                .first { $0.tag.id == "mood/calm" }
        )
        let undoManager = UndoManager()

        #expect(
            model.performTagEdit(
                .acceptSuggestion(
                    tagID: suggestion.tag.id,
                    targets: suggestion.eligibleTargets
                ),
                undoManager: undoManager
            )
        )
        #expect(
            model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "mood/calm", target: .track(1))
            )
        )
        undoManager.undo()
        #expect(
            !model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "mood/calm", target: .track(1))
            )
        )
    }

    @Test("Dismiss creates no assignment and supports Undo and Redo")
    func dismissUndo() {
        let model = CadenceAppModel.preview(
            tagAssignments: assignments(
                adding: "mood/calm",
                toTracks: [2, 3, 4, 5, 6, 7]
            )
        )
        let dismissUndoManager = UndoManager()
        #expect(
            model.performTagEdit(
                .dismissSuggestion(tagID: "mood/calm", targets: [.track(1)]),
                undoManager: dismissUndoManager
            )
        )
        #expect(
            model.dismissedTagSuggestions.contains(
                TagSuggestionDismissal(tagID: "mood/calm", target: .track(1))
            )
        )
        #expect(
            !model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "mood/calm", target: .track(1))
            )
        )

        dismissUndoManager.undo()
        #expect(model.dismissedTagSuggestions.isEmpty)
        dismissUndoManager.redo()
        #expect(
            model.dismissedTagSuggestions.contains(
                TagSuggestionDismissal(tagID: "mood/calm", target: .track(1))
            )
        )
    }

    @Test("Accept revalidates a stale suggestion before assigning")
    func staleAccept() {
        let model = CadenceAppModel.preview(
            tagAssignments: assignments(
                adding: "mood/calm",
                toTracks: [2, 3, 4, 5, 6, 7]
            )
        )

        #expect(
            model.performTagEdit(
                .removeDirect(
                    tagID: "mood/calm",
                    targets: [2, 3, 4, 5, 6, 7].map(TagAssignmentTarget.track)
                )
            )
        )
        #expect(
            !model.performTagEdit(
                .acceptSuggestion(tagID: "mood/calm", targets: [.track(1)])
            )
        )
        #expect(
            !model.tagAssignments.contains(
                TagAssignmentPreview(tagID: "mood/calm", target: .track(1))
            )
        )
    }

    private func assignments(
        adding tagID: TagPreview.ID,
        toTracks trackIDs: [TrackPreview.ID]
    ) -> Set<TagAssignmentPreview> {
        var assignments = Set<TagAssignmentPreview>.mockTagAssignments
        assignments = assignments.filter { assignment in
            guard assignment.tagID == tagID else {
                return true
            }
            if case .track = assignment.target {
                return false
            }
            return true
        }
        assignments.formUnion(
            trackIDs.map {
                TagAssignmentPreview(tagID: tagID, target: .track($0))
            }
        )
        return assignments
    }
}
