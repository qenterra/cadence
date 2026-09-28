@testable import Cadence
import Foundation
import SwiftData
import Testing

@MainActor
struct TagRenameTests {
    @Test("Renaming a tag preserves its track assignments")
    func renameTagPreservesAssignments() async throws {
        let fixture = try makeFixture()

        let repository = LibraryRepository(modelContainer: fixture.container)
        let tagID = try await repository.createTagAndAssign(
            displayPath: "Mood / Calm",
            trackID: fixture.tracks[0].id
        )
        let renamed = try await repository.renameTag(
            id: tagID,
            displayPath: "Mood / Focused"
        )
        let states = try await repository.tagStates(trackID: fixture.tracks[0].id)

        #expect(renamed.id == tagID)
        #expect(renamed.displayPath == "Mood / Focused")
        #expect(states.map(\.tag.id) == [tagID])
        #expect(states.map(\.tag.displayPath) == ["Mood / Focused"])
    }

    @Test("Removing a direct tag preserves the tag and assignments on other tracks")
    func removingDirectTagPreservesEntityAndOtherAssignments() async throws {
        let fixture = try makeFixture()
        let repository = LibraryRepository(modelContainer: fixture.container)
        let tagID = try await repository.createTagAndAssign(
            displayPath: "Mood / Calm",
            trackID: fixture.tracks[0].id
        )
        try await repository.setTag(tagID, assigned: true, trackID: fixture.tracks[1].id)

        try await repository.setTag(tagID, assigned: false, trackID: fixture.tracks[0].id)

        let removedTrackStates = try await repository.tagStates(trackID: fixture.tracks[0].id)
        let retainedTrackStates = try await repository.tagStates(trackID: fixture.tracks[1].id)
        let tags = try await repository.tagsPage().items
        #expect(removedTrackStates.isEmpty)
        #expect(retainedTrackStates.map(\.tag.id) == [tagID])
        #expect(tags.contains { $0.id == tagID })
    }

    @Test("Removing an inherited tag creates a reversible per-track exclusion")
    func removingInheritedTagCreatesExclusion() async throws {
        let fixture = try makeFixture()
        let repository = LibraryRepository(modelContainer: fixture.container)
        let tagID = try await repository.createTag(displayPath: "Era / 1990s")
        try await repository.assignTag(tagID, albumID: fixture.album.id)

        let inherited = try await repository.tagStates(trackID: fixture.tracks[0].id)
        #expect(inherited.map(\.source) == [.inherited])

        try await repository.setTag(tagID, assigned: false, trackID: fixture.tracks[0].id)

        let excluded = try await repository.tagStates(trackID: fixture.tracks[0].id)
        let sibling = try await repository.tagStates(trackID: fixture.tracks[1].id)
        #expect(excluded.isEmpty)
        #expect(sibling.map(\.tag.id) == [tagID])

        try await repository.setTag(tagID, assigned: true, trackID: fixture.tracks[0].id)

        let restored = try await repository.tagStates(trackID: fixture.tracks[0].id)
        #expect(restored.map(\.source) == [.inherited])
        #expect(restored.map(\.tag.id) == [tagID])
    }

    @Test("A duplicate rename leaves both tag names and assignments unchanged")
    func duplicateRenamePreservesAssociations() async throws {
        let fixture = try makeFixture()
        let repository = LibraryRepository(modelContainer: fixture.container)
        let calmID = try await repository.createTagAndAssign(
            displayPath: "Mood / Calm",
            trackID: fixture.tracks[0].id
        )
        try await repository.setTag(calmID, assigned: true, trackID: fixture.tracks[1].id)
        let focusID = try await repository.createTagAndAssign(
            displayPath: "Mood / Focus",
            trackID: fixture.tracks[0].id
        )

        do {
            _ = try await repository.renameTag(id: calmID, displayPath: "Mood / Focus")
            Issue.record("Expected duplicate tag rename to fail")
        } catch let error as ProductionTagEditError {
            guard case .duplicatePath = error else {
                Issue.record("Expected duplicatePath, received \(error)")
                return
            }
        }

        let firstTrackStates = try await repository.tagStates(trackID: fixture.tracks[0].id)
        let secondTrackStates = try await repository.tagStates(trackID: fixture.tracks[1].id)
        let tags = try await repository.tagsPage().items
        #expect(Set(firstTrackStates.map(\.tag.id)) == Set([calmID, focusID]))
        #expect(secondTrackStates.map(\.tag.id) == [calmID])
        #expect(Set(tags.map(\.displayPath)) == Set(["Mood / Calm", "Mood / Focus"]))
    }
}

private extension TagRenameTests {
    struct Fixture {
        let container: ModelContainer
        let album: AlbumRecord
        let tracks: [TrackRecord]
    }

    func makeFixture() throws -> Fixture {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let importID = UUID()
        let artist = ArtistRecord(name: "Artist", trackCount: 2, albumCount: 1)
        let album = AlbumRecord(
            title: "Album",
            artist: artist,
            trackCount: 2,
            totalDuration: 360
        )
        let tracks = (0 ..< 2).map { index in
            let trackID = UUID()
            return TrackRecord(
                id: trackID,
                originalFilename: "Track \(index + 1).flac",
                title: "Track \(index + 1)",
                duration: 180,
                codec: "FLAC",
                container: "FLAC",
                sampleRate: 48000,
                channelCount: 2,
                bitDepth: 24,
                contentHash: String(repeating: String(index), count: 64),
                relativeMediaPath: "Media/\(trackID.uuidString).flac",
                importSessionID: importID,
                artist: artist,
                album: album
            )
        }
        context.insert(artist)
        context.insert(album)
        tracks.forEach(context.insert)
        try context.save()
        return Fixture(container: container, album: album, tracks: tracks)
    }
}
