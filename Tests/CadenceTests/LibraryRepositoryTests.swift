@testable import Cadence
import Foundation
import SwiftData
import Testing

struct LibraryRepositoryTests {
    @Test("Track pages use stable cursors and never exceed 200 records")
    func trackPaging() async throws {
        let container = try makeContainer(trackCount: 205)
        let repository = LibraryRepository(modelContainer: container)

        let firstPage = try await repository.tracksPage(limit: 500)
        let secondPage = try await repository.tracksPage(
            after: firstPage.nextCursor,
            limit: 500
        )
        let allIDs = firstPage.items.map(\.id) + secondPage.items.map(\.id)

        #expect(firstPage.items.count == 200)
        #expect(firstPage.nextCursor != nil)
        #expect(secondPage.items.count == 5)
        #expect(secondPage.nextCursor == nil)
        #expect(Set(allIDs).count == 205)
    }

    @Test("Normalized title search remains bounded and diacritic insensitive")
    func normalizedSearch() async throws {
        let container = try makeContainer(
            titles: [
                "Échoes in Reverse",
                "Midnight Static",
                "Echo Chamber",
            ]
        )
        let repository = LibraryRepository(modelContainer: container)

        let page = try await repository.tracksPage(
            search: "  ECHO ",
            limit: 200
        )

        #expect(
            page.items.map(\.title)
                == ["Echo Chamber", "Échoes in Reverse"]
        )
        #expect(page.nextCursor == nil)
    }

    @Test("Playback projections preserve requested queue order")
    func orderedPlaybackProjection() async throws {
        let container = try makeContainer(trackCount: 4)
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<TrackRecord>(
            sortBy: [SortDescriptor(\.normalizedTitle)]
        )
        let records = try context.fetch(descriptor)
        let requestedIDs = [
            records[2].id,
            records[0].id,
            records[3].id,
        ]
        let repository = LibraryRepository(modelContainer: container)

        let projections = try await repository.playbackTracks(
            ids: requestedIDs
        )

        #expect(projections.map(\.id) == requestedIDs)
        #expect(projections.allSatisfy { $0.relativeMediaPath.hasPrefix("Media/") })
    }

    @Test("Exact hash lookup is explicit and committed data stays immutable")
    func exactHashLookup() async throws {
        let container = try makeContainer(trackCount: 1)
        let context = ModelContext(container)
        let track = try #require(
            try context.fetch(FetchDescriptor<TrackRecord>()).first
        )
        let repository = LibraryRepository(modelContainer: container)

        #expect(try await repository.containsExactHash(track.contentHash))
        #expect(
            try await !repository.containsExactHash(
                String(repeating: "f", count: 64)
            )
        )
    }

    @Test("Artist and album pages use the same bounded cursor contract")
    func artistAndAlbumPaging() async throws {
        let container = try makeArtistAlbumContainer(count: 205)
        let repository = LibraryRepository(modelContainer: container)

        let artists = try await repository.artistsPage(limit: 500)
        let albums = try await repository.albumsPage(limit: 500)
        let remainingArtists = try await repository.artistsPage(
            after: artists.nextCursor,
            limit: 500
        )
        let remainingAlbums = try await repository.albumsPage(
            after: albums.nextCursor,
            limit: 500
        )

        #expect(artists.items.count == 200)
        #expect(albums.items.count == 200)
        #expect(remainingArtists.items.count == 5)
        #expect(remainingAlbums.items.count == 5)
        #expect(remainingArtists.nextCursor == nil)
        #expect(remainingAlbums.nextCursor == nil)
    }

    @Test("Duplicate evidence distinguishes hash from normalized identity")
    func importDuplicateEvidence() async throws {
        let container = try makeContainer(
            titles: ["Échoes in Reverse", "Other Song"]
        )
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [SortDescriptor(\.normalizedTitle)]
            )
        )
        let existing = try #require(
            records.first { $0.title == "Échoes in Reverse" }
        )
        let repository = LibraryRepository(modelContainer: container)
        let exactIdentity = ImportMetadataIdentity(
            artist: "Repository Artist",
            title: "Different Title"
        )
        let metadataIdentity = ImportMetadataIdentity(
            artist: "Repository Artist",
            title: "echoes in reverse"
        )

        let evidence = try await repository.importDuplicateEvidence(
            probes: [
                ImportDuplicateProbe(
                    contentHash: existing.contentHash,
                    identity: exactIdentity
                ),
                ImportDuplicateProbe(
                    contentHash: "uncommitted-hash",
                    identity: metadataIdentity
                ),
            ]
        )

        #expect(evidence.exactHashes == [existing.contentHash])
        #expect(evidence.metadataIdentities == [metadataIdentity])
    }

    @Test("Production tag editing respects inherited tags and exclusions")
    func productionTagEditing() async throws {
        let container = try makeContainer(trackCount: 1)
        let context = ModelContext(container)
        let track = try #require(
            try context.fetch(FetchDescriptor<TrackRecord>()).first
        )
        let album = try #require(track.album)
        let inheritedTag = TagRecord(
            displayPath: "mood/sad",
            groupPath: "mood"
        )
        context.insert(inheritedTag)
        context.insert(
            TagAssignmentRecord(
                targetKind: .album,
                targetID: album.id,
                tagID: inheritedTag.id
            )
        )
        try context.save()

        let repository = LibraryRepository(modelContainer: container)
        var states = try await repository.tagStates(trackID: track.id)
        #expect(states.map(\.tag.id) == [inheritedTag.id])
        #expect(states.first?.source == .inherited)

        try await repository.setTag(
            inheritedTag.id,
            assigned: false,
            trackID: track.id
        )
        states = try await repository.tagStates(trackID: track.id)
        #expect(states.isEmpty)

        try await repository.setTag(
            inheritedTag.id,
            assigned: true,
            trackID: track.id
        )
        states = try await repository.tagStates(trackID: track.id)
        #expect(states.map(\.tag.id) == [inheritedTag.id])
        #expect(states.first?.source == .inherited)
    }

    @Test("Creating a tag normalizes it and immediately assigns the track")
    func createProductionTag() async throws {
        let container = try makeContainer(trackCount: 1)
        let context = ModelContext(container)
        let track = try #require(
            try context.fetch(FetchDescriptor<TrackRecord>()).first
        )
        let repository = LibraryRepository(modelContainer: container)

        let tagID = try await repository.createTagAndAssign(
            displayPath: "  Context / Rainy Day  ",
            trackID: track.id
        )
        let states = try await repository.tagStates(trackID: track.id)

        #expect(states.map(\.tag.id) == [tagID])
        #expect(states.first?.tag.displayPath == "Context / Rainy Day")
        #expect(states.first?.source == .direct)
    }
}

private extension LibraryRepositoryTests {
    private func makeContainer(
        trackCount: Int
    ) throws -> ModelContainer {
        try makeContainer(
            titles: (0 ..< trackCount).map {
                "Track \(String(format: "%03d", $0))"
            }
        )
    }

    private func makeContainer(
        titles: [String]
    ) throws -> ModelContainer {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let importID = UUID()
        let artist = ArtistRecord(
            name: "Repository Artist",
            trackCount: titles.count,
            albumCount: 1
        )
        let album = AlbumRecord(
            title: "Repository Album",
            artist: artist,
            trackCount: titles.count,
            totalDuration: Double(titles.count) * 180
        )
        let session = ImportSessionRecord(
            id: importID,
            sourceDisplayName: "Fixture",
            state: .complete,
            importedCount: titles.count
        )

        context.insert(session)
        context.insert(artist)
        context.insert(album)

        for (index, title) in titles.enumerated() {
            let hash = String(format: "%064x", index + 1)
            let trackID = UUID()
            let track = TrackRecord(
                id: trackID,
                originalFilename: "\(title).flac",
                title: title,
                duration: 180,
                codec: "FLAC",
                container: "FLAC",
                sampleRate: 48000,
                channelCount: 2,
                bitDepth: 24,
                contentHash: hash,
                relativeMediaPath: "Media/\(trackID.uuidString).flac",
                importSessionID: importID,
                artist: artist,
                album: album,
                trackNumber: index + 1
            )
            context.insert(track)
        }

        try context.save()
        return container
    }

    private func makeArtistAlbumContainer(
        count: Int
    ) throws -> ModelContainer {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)

        for index in 0 ..< count {
            let artist = ArtistRecord(
                name: "Artist \(String(format: "%03d", index))",
                albumCount: 1
            )
            let album = AlbumRecord(
                title: "Album \(String(format: "%03d", index))",
                artist: artist
            )
            context.insert(artist)
            context.insert(album)
        }

        try context.save()
        return container
    }
}
