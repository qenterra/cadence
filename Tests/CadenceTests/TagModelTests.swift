@testable import Cadence
import Testing

struct TagPreviewTests {
    @Test("Tag paths normalize hierarchy and reject empty components")
    func pathNormalization() throws {
        let hierarchical = try #require(TagPreview(path: " Genre / Ambient "))
        let standalone = try #require(TagPreview(path: "childhood"))

        #expect(hierarchical.id == "genre/ambient")
        #expect(hierarchical.displayName == "Ambient")
        #expect(hierarchical.groupID == .hierarchy("genre"))
        #expect(standalone.groupID == .standalone)
        let rainyDay = try #require(TagPreview(path: "context/rainy-day"))
        #expect(rainyDay.displayPath == "Context / Rainy Day")
        #expect(TagPreview(path: "genre//ambient") == nil)
        #expect(TagPreview(path: "/ambient") == nil)
        #expect(TagPreview(path: "ambient/") == nil)
        #expect(TagPreview(path: "   ") == nil)
        #expect(TagPreview.validationError(for: "/genre") == .emptyComponent)
        #expect(TagPreview.validationError(for: "genre/") == .emptyComponent)
        #expect(TagPreview.validationError(for: "genre//ambient") == .emptyComponent)
        #expect(TagPreview.validationError(for: "  ") == .empty)
    }
}

@MainActor
struct CadenceTagModelTests {
    @Test("Tag groups keep virtual groups and localized canonical order")
    func groupOrdering() {
        let model = CadenceAppModel()

        #expect(
            model.tagGroups.map(\.title)
                == ["All Tags", "Context", "Genre", "Mood", "Standalone"]
        )

        let originalOrder = model.tagGroups.map(\.id)
        if let mood = model.tagGroups.first(where: { $0.id == .hierarchy("mood") }) {
            model.selectTagGroup(mood)
        }

        #expect(model.tagGroups.map(\.id) == originalOrder)
        #expect(model.tagsForSelectedGroup.allSatisfy { $0.groupID == .hierarchy("mood") })
    }

    @Test("Album tags are inherited without copied track assignments")
    func albumInheritance() throws {
        let model = CadenceAppModel()
        let track = try #require(model.tracks.first { $0.id == 1 })

        #expect(model.tagMatchSource(for: track, tagID: "genre/ambient") == .inherited)
        #expect(
            !model.tagAssignments.contains(
                TagAssignmentPreview(
                    tagID: "genre/ambient",
                    target: .track(track.id)
                )
            )
        )
    }

    @Test("Track assignments combine with inheritance")
    func directAndInheritedTags() throws {
        let model = CadenceAppModel()
        let track = try #require(model.tracks.first { $0.id == 1 })
        let effectiveTagIDs = Set(model.effectiveTags(for: track).map(\.id))

        #expect(effectiveTagIDs.contains("genre/ambient"))
        #expect(effectiveTagIDs.contains("genre/electronic"))
        #expect(effectiveTagIDs.contains("mood/sad"))
        #expect(model.tagMatchSource(for: track, tagID: "mood/sad") == .direct)
    }

    @Test("Track exclusions remove only inherited album tags")
    func inheritedExclusion() throws {
        let model = CadenceAppModel()
        let excludedTrack = try #require(model.tracks.first { $0.id == 9 })
        let inheritedTrack = try #require(model.tracks.first { $0.id == 1 })

        #expect(model.tagMatchSource(for: excludedTrack, tagID: "context/night") == nil)
        #expect(model.tagMatchSource(for: inheritedTrack, tagID: "context/night") == .inherited)
        #expect(model.tagMatchSource(for: excludedTrack, tagID: "genre/ambient") == .inherited)
    }

    @Test("Tag results distinguish album and track assignment sources")
    func resultSources() throws {
        let model = CadenceAppModel()
        let ambient = try #require(model.tags.first { $0.id == "genre/ambient" })
        model.selectTag(ambient)

        let inheritedTrack = try #require(model.taggedTracks.first { $0.track.id == 1 })
        let directTrack = try #require(model.taggedTracks.first { $0.track.id == 31 })
        let albumAssignment = try #require(
            model.taggedAlbums.first { $0.album.title == "Signals After Dark" }
        )
        let trackMatch = try #require(
            model.taggedAlbums.first { $0.album.title == "Nocturnes for Empty Roads" }
        )

        #expect(inheritedTrack.source == .inherited)
        #expect(directTrack.source == .direct)
        #expect(albumAssignment.source == .album)
        #expect(trackMatch.source == .track)
    }

    @Test("Library search includes effective tag paths")
    func searchByTag() {
        let model = CadenceAppModel()
        model.searchScope = .library
        model.searchQuery = "mood/sad"

        #expect(model.visibleTracks.map(\.id) == [1])
    }
}
