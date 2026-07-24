@testable import Cadence
import Testing

@MainActor
struct TagEditingNavigationTests {
    @Test("A library track opens as the exact target in the tag editor")
    func libraryTrackEntryPoint() throws {
        let model = CadenceAppModel()
        let track = try #require(model.tracks.first { $0.id == 21 })

        model.openTagEditor(for: track)

        #expect(model.selectedDestination == .tags)
        #expect(model.tagResultScope == .tracks)
        #expect(model.selectedTagGroupID == .all)
        #expect(model.selectedTagID == "genre/shoegaze")
        #expect(model.tagEditingSelection.targets == [.track(track.id)])
        #expect(model.selectedTrackID == track.id)
        #expect(model.isTagInspectorPresented)
    }

    @Test("An untagged library track remains editable after its first assignment")
    func untaggedLibraryTrackEntryPoint() throws {
        let model = CadenceAppModel()
        let track = try #require(model.tracks.first { $0.id == 26 })
        #expect(model.effectiveTags(for: track).isEmpty)

        model.openTagEditor(for: track)
        #expect(model.selectedTagID == nil)

        #expect(
            model.performTagEdit(
                .assign(tagID: "roadtrip", targets: [.track(track.id)])
            )
        )
        #expect(model.tagEditingSelection.targets == [.track(track.id)])
        #expect(model.isTagInspectorPresented)
    }

    @Test("Select All targets every visible result in canonical order")
    func selectAllTagResults() throws {
        let model = CadenceAppModel()
        let ambient = try #require(
            model.tags.first { $0.id == "genre/ambient" }
        )
        model.selectTag(ambient)

        model.selectAllTagResults()

        let expectedTargets = model.taggedTracks.map {
            TagAssignmentTarget.track($0.track.id)
        }
        #expect(!expectedTargets.isEmpty)
        #expect(model.tagEditingSelection.targets == expectedTargets)
        #expect(model.tagEditingSelection.primaryTarget == expectedTargets.first)
    }
}
