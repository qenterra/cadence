@testable import Cadence
import Foundation
import SwiftData
import Testing

struct TagSmartCollectionRemediationTests {
    @Test("Tag pages and the store expose records after the first 200")
    @MainActor
    func tagPaging() async throws {
        let container = try makeContainer(trackCount: 1)
        let context = ModelContext(container)
        for index in 0 ..< 205 {
            context.insert(
                TagRecord(
                    displayPath: "tag/\(String(format: "%03d", index))",
                    groupPath: "tag"
                )
            )
        }
        try context.save()

        let repository = LibraryRepository(modelContainer: container)
        let firstPage = try await repository.tagsPage(limit: 500)
        let secondPage = try await repository.tagsPage(
            after: firstPage.nextCursor,
            limit: 500
        )
        let ruleData = try await repository
            .productionSmartCollectionRuleData()

        #expect(firstPage.items.count == 200)
        #expect(secondPage.items.count == 5)
        #expect(secondPage.nextCursor == nil)
        #expect(ruleData.tags.count == 205)

        let store = LibraryStore(container: container)
        await store.loadInitialLibrary()
        #expect(store.tags.count == 200)
        #expect(store.canLoadMoreTags)

        await store.loadNextTags()
        #expect(store.tags.count == 205)
        #expect(!store.canLoadMoreTags)
        #expect(Set(store.tags.map(\.id)).count == 205)
    }

    @Test("Batch tag assignment chunks more than 1000 track IDs")
    func largeBatchTagAssignment() async throws {
        let container = try makeContainer(trackCount: 1005)
        let context = ModelContext(container)
        let trackIDs = try context.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [SortDescriptor(\.normalizedTitle)]
            )
        ).map(\.id)
        let repository = LibraryRepository(modelContainer: container)
        let tagID = try await repository.createTag(
            displayPath: "workflow/reviewed"
        )

        try await repository.assignTag(tagID, trackIDs: trackIDs)

        #expect(
            try await repository.directlyAssignedTrackIDs(tagID: tagID)
                == Set(trackIDs)
        )
    }

    @Test("Smart Collection facets include values after track page 200")
    func smartCollectionFacetsUseFullCatalog() async throws {
        let container = try makeContainer(trackCount: 205)
        let context = ModelContext(container)
        let tracks = try context.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [SortDescriptor(\.normalizedTitle)]
            )
        )
        let lateTrack = try #require(tracks.last)
        let lateArtist = ArtistRecord(name: "Zulu Facet Artist")
        let lateAlbum = AlbumRecord(
            title: "Zulu Facet Album",
            artist: lateArtist,
            year: 2037
        )
        context.insert(lateArtist)
        context.insert(lateAlbum)
        lateTrack.artist = lateArtist
        lateTrack.album = lateAlbum
        lateTrack.codec = "DSD"
        try context.save()

        let repository = LibraryRepository(modelContainer: container)
        let data = try await repository.productionSmartCollectionRuleData()

        #expect(data.options.artists.contains("Zulu Facet Artist"))
        #expect(data.options.albums.contains("Zulu Facet Album"))
        #expect(data.options.years.contains(2037))
        #expect(data.options.formats.contains("DSD"))
    }

    @Test("Repository Smart Collections preserve inheritance and exclusions")
    func smartCollectionEffectiveTagSemantics() async throws {
        let container = try makeContainer(trackCount: 3)
        let context = ModelContext(container)
        let tracks = try context.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [SortDescriptor(\.normalizedTitle)]
            )
        )
        let album = try #require(tracks.first?.album)
        let tag = TagRecord(
            displayPath: "genre/ambient",
            groupPath: "genre"
        )
        insertEffectiveTagFixture(
            context: context,
            tracks: tracks,
            album: album,
            tag: tag
        )
        try context.save()

        let rule = exactTagRule(tagID: tag.id)
        let repository = LibraryRepository(modelContainer: container)
        let evaluation = try await repository
            .evaluateProductionSmartCollection(root: rule)

        #expect(evaluation.orderedTrackIDs == [tracks[0].id, tracks[2].id])
    }

    @Test("Smart Collection results page projections without truncating totals")
    @MainActor
    func smartCollectionResultPaging() async throws {
        let container = try makeContainer(trackCount: 205)
        let store = LibraryStore(container: container)
        let rule = SmartCollectionRuleGroup(
            combinator: .all,
            children: []
        )

        await store.loadSmartCollectionResult(rule: rule)

        #expect(store.smartCollectionSummary(for: rule).count == 205)
        #expect(store.smartCollectionTracks(for: rule).count == 200)

        await store.loadNextSmartCollectionResult(rule: rule)

        #expect(store.smartCollectionTracks(for: rule).count == 205)
        #expect(
            Set(store.smartCollectionTracks(for: rule).map(\.id)).count == 205
        )
        #expect(!SmartCollectionRuleField.productionCases.contains(.rating))
    }
}

private extension TagSmartCollectionRemediationTests {
    func makeContainer(trackCount: Int) throws -> ModelContainer {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let importID = UUID()
        let artist = ArtistRecord(
            name: "Repository Artist",
            trackCount: trackCount,
            albumCount: 1
        )
        let album = AlbumRecord(
            title: "Repository Album",
            artist: artist,
            trackCount: trackCount,
            totalDuration: Double(trackCount) * 180
        )
        let session = ImportSessionRecord(
            id: importID,
            sourceDisplayName: "Fixture",
            state: .complete,
            importedCount: trackCount
        )
        context.insert(session)
        context.insert(artist)
        context.insert(album)

        for index in 0 ..< trackCount {
            let id = UUID()
            context.insert(
                TrackRecord(
                    id: id,
                    originalFilename: "Track \(index).flac",
                    title: "Track \(String(format: "%04d", index))",
                    duration: 180,
                    codec: "FLAC",
                    container: "FLAC",
                    sampleRate: 48000,
                    channelCount: 2,
                    bitDepth: 24,
                    contentHash: String(format: "%064x", index + 1),
                    relativeMediaPath: "Media/\(id.uuidString).flac",
                    importSessionID: importID,
                    artist: artist,
                    album: album,
                    trackNumber: index + 1
                )
            )
        }
        try context.save()
        return container
    }

    func insertEffectiveTagFixture(
        context: ModelContext,
        tracks: [TrackRecord],
        album: AlbumRecord,
        tag: TagRecord
    ) {
        context.insert(tag)
        context.insert(
            TagAssignmentRecord(
                targetKind: .album,
                targetID: album.id,
                tagID: tag.id
            )
        )
        context.insert(
            TagAssignmentRecord(
                targetKind: .track,
                targetID: tracks[0].id,
                tagID: tag.id
            )
        )
        for track in tracks.prefix(2) {
            context.insert(
                TagExclusionRecord(
                    trackID: track.id,
                    tagID: tag.id
                )
            )
        }
    }

    func exactTagRule(tagID: UUID) -> SmartCollectionRuleGroup {
        SmartCollectionRuleGroup(
            combinator: .all,
            children: [
                .condition(
                    SmartCollectionRuleCondition(
                        field: .tag,
                        operator: .is,
                        value: .tag(
                            id: tagID.uuidString,
                            scope: .exact
                        )
                    )
                ),
            ]
        )
    }
}
