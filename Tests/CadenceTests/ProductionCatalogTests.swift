@testable import Cadence
import Foundation
import SwiftData
import Testing

struct ProductionCatalogTests {
    @Test("Catalog projections expose details, relationships, counts, and tags")
    func catalogProjection() async throws {
        let fixture = try makeCatalogFixture()
        let repository = LibraryRepository(modelContainer: fixture.container)

        let counts = try await repository.catalogCounts()
        let artist = try await repository.artist(id: fixture.artistID)
        let album = try await repository.album(id: fixture.albumID)
        let albumTracks = try await repository.tracks(albumID: fixture.albumID)
        let artistTracks = try await repository.tracks(artistID: fixture.artistID)
        let artistAlbums = try await repository.albums(artistID: fixture.artistID)
        let tags = try await repository.tagsPage()
        let taggedTracks = try await repository.tracks(tagID: fixture.tagID)

        #expect(counts.liveTrackCount == 2)
        #expect(counts.trashedTrackCount == 0)
        #expect(artist?.name == "North Assembly")
        #expect(album?.title == "Signals After Dark")
        #expect(albumTracks.items.map(\.title) == ["Glass Horizon", "Midnight Static"])
        #expect(artistTracks.items.map(\.title) == ["Glass Horizon", "Midnight Static"])
        #expect(artistAlbums.map(\.title) == ["Signals After Dark"])
        #expect(tags.items.map(\.displayPath) == ["genre/ambient"])
        #expect(taggedTracks.items.map(\.title) == ["Midnight Static"])
    }

    @Test("Grouped catalog search returns matching tracks, albums, artists, and tags")
    func groupedSearch() async throws {
        let fixture = try makeCatalogFixture()
        let repository = LibraryRepository(modelContainer: fixture.container)

        let trackResults = try await repository.catalogSearch(query: "midnight")
        let albumResults = try await repository.catalogSearch(query: "signals")
        let artistResults = try await repository.catalogSearch(query: "north")
        let tagResults = try await repository.catalogSearch(query: "ambient")

        #expect(trackResults.tracks.map(\.title) == ["Midnight Static"])
        #expect(albumResults.albums.map(\.title) == ["Signals After Dark"])
        #expect(artistResults.artists.map(\.name) == ["North Assembly"])
        #expect(tagResults.tags.map(\.displayPath) == ["genre/ambient"])
    }

    @Test("Playback projection contains complete routing and ordering metadata")
    func playbackProjectionMetadata() async throws {
        let fixture = try makeCatalogFixture()
        let repository = LibraryRepository(modelContainer: fixture.container)

        let tracks = try await repository.playbackTracks(ids: [fixture.trackID])
        let track = try #require(tracks.first)

        #expect(track.year == 2026)
        #expect(track.discNumber == 1)
        #expect(track.trackNumber == 2)
        #expect(track.artistID == fixture.artistID)
        #expect(track.albumID == fixture.albumID)
    }

    @Test("Album and artist favorite state is persisted by the production repository")
    func favoriteMutations() async throws {
        let fixture = try makeCatalogFixture()
        let repository = LibraryRepository(modelContainer: fixture.container)
        let timestamp = Date(timeIntervalSince1970: 1_786_000_000)

        _ = try await repository.setAlbumFavorite(
            id: fixture.albumID,
            isFavorite: true,
            at: timestamp
        )
        _ = try await repository.setArtistFavorite(
            id: fixture.artistID,
            isFavorite: true,
            at: timestamp
        )

        let album = try #require(
            try await repository.album(id: fixture.albumID)
        )
        let artist = try #require(
            try await repository.artist(id: fixture.artistID)
        )
        #expect(album.isFavorite)
        #expect(album.favoriteDate == timestamp)
        #expect(artist.isFavorite)
        #expect(artist.favoriteDate == timestamp)

        _ = try await repository.setAlbumFavorite(
            id: fixture.albumID,
            isFavorite: false,
            at: .distantFuture
        )
        _ = try await repository.setArtistFavorite(
            id: fixture.artistID,
            isFavorite: false,
            at: .distantFuture
        )

        #expect(try await repository.album(id: fixture.albumID)?.isFavorite == false)
        #expect(try await repository.artist(id: fixture.artistID)?.isFavorite == false)
    }

    private func makeCatalogFixture() throws -> CatalogFixture {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let importID = UUID()
        let records = makeCatalogRecords(importID: importID)

        insertFixtureRecords(context: context, records: records)
        try context.save()

        return CatalogFixture(
            container: container,
            artistID: records.artist.id,
            albumID: records.album.id,
            trackID: records.firstTrack.id,
            tagID: records.tag.id
        )
    }

    private func makeCatalogRecords(
        importID: UUID
    ) -> CatalogRecords {
        let artist = ArtistRecord(
            name: "North Assembly",
            trackCount: 2,
            albumCount: 1
        )
        let album = AlbumRecord(
            title: "Signals After Dark",
            artist: artist,
            year: 2026,
            trackCount: 2,
            totalDuration: 480
        )
        let session = ImportSessionRecord(
            id: importID,
            sourceDisplayName: "Fixture",
            state: .complete,
            importedCount: 2
        )
        let firstTrack = makeTrack(
            seed: CatalogTrackSeed(
                title: "Midnight Static",
                hashCharacter: "1",
                trackNumber: 2
            ),
            importID: importID,
            artist: artist,
            album: album
        )
        let secondTrack = makeTrack(
            seed: CatalogTrackSeed(
                title: "Glass Horizon",
                hashCharacter: "2",
                trackNumber: 1
            ),
            importID: importID,
            artist: artist,
            album: album
        )
        let tagRecords = makeTagRecords(trackID: firstTrack.id)

        return CatalogRecords(
            artist: artist,
            album: album,
            session: session,
            firstTrack: firstTrack,
            secondTrack: secondTrack,
            tag: tagRecords.tag,
            assignment: tagRecords.assignment
        )
    }

    private func makeTagRecords(
        trackID: UUID
    ) -> (tag: TagRecord, assignment: TagAssignmentRecord) {
        let tag = TagRecord(
            displayPath: "genre/ambient",
            groupPath: "genre"
        )
        return (
            tag,
            TagAssignmentRecord(
                targetKind: .track,
                targetID: trackID,
                tagID: tag.id
            )
        )
    }

    private func makeTrack(
        seed: CatalogTrackSeed,
        importID: UUID,
        artist: ArtistRecord,
        album: AlbumRecord
    ) -> TrackRecord {
        let id = UUID()
        return TrackRecord(
            id: id,
            originalFilename: "\(seed.title).flac",
            title: seed.title,
            duration: 240,
            codec: "FLAC",
            container: "FLAC",
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            contentHash: String(repeating: seed.hashCharacter, count: 64),
            relativeMediaPath: "Media/\(id.uuidString).flac",
            importSessionID: importID,
            artist: artist,
            album: album,
            trackNumber: seed.trackNumber,
            discNumber: 1
        )
    }

    private func insertFixtureRecords(
        context: ModelContext,
        records: CatalogRecords
    ) {
        context.insert(records.artist)
        context.insert(records.album)
        context.insert(records.session)
        context.insert(records.firstTrack)
        context.insert(records.secondTrack)
        context.insert(records.tag)
        context.insert(records.assignment)
    }
}

private struct CatalogTrackSeed {
    let title: String
    let hashCharacter: String
    let trackNumber: Int
}

private struct CatalogRecords {
    let artist: ArtistRecord
    let album: AlbumRecord
    let session: ImportSessionRecord
    let firstTrack: TrackRecord
    let secondTrack: TrackRecord
    let tag: TagRecord
    let assignment: TagAssignmentRecord
}

private struct CatalogFixture {
    let container: ModelContainer
    let artistID: UUID
    let albumID: UUID
    let trackID: UUID
    let tagID: UUID
}
