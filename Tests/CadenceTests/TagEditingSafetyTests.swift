@testable import Cadence
import Testing

@MainActor
struct TagEditingSafetyTests {
    @Test("Commands ignore targets missing from the library")
    func missingTargets() {
        var assignments = Set<TagAssignmentPreview>.mockTagAssignments
        let staleAssignment = TagAssignmentPreview(
            tagID: "roadtrip",
            target: .track(999)
        )
        assignments.insert(staleAssignment)

        var exclusions = Set<TagExclusionPreview>.mockTagExclusions
        let staleExclusion = TagExclusionPreview(
            tagID: "context/night",
            trackID: 999
        )
        exclusions.insert(staleExclusion)

        let model = CadenceAppModel.testFixture(
            tagAssignments: assignments,
            tagExclusions: exclusions
        )

        #expect(
            !model.performTagEdit(
                .removeDirect(tagID: "roadtrip", targets: [.track(999)])
            )
        )
        #expect(
            !model.performTagEdit(
                .restoreInheritance(tagID: "context/night", trackIDs: [999])
            )
        )
        #expect(model.tagAssignments.contains(staleAssignment))
        #expect(model.tagExclusions.contains(staleExclusion))
    }
}
