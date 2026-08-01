@testable import Cadence
import Foundation
import SwiftData
import Testing

struct CatalogPagingTests {
    @Test("Repository sorting is global across 401 records in both directions")
    func globalSortingAcrossPages() async throws {
        let fixture = try makeLargeRelationshipFixture()
        let repository = LibraryRepository(modelContainer: fixture.container)

        let ascending = try await allTracks(
            repository: repository,
            query: LibraryTrackQuery(
                sort: LibraryTrackSort(
                    field: .playCount,
                    direction: .ascending
                )
            )
        )
        let descending = try await allTracks(
            repository: repository,
            query: LibraryTrackQuery(
                sort: LibraryTrackSort(
                    field: .playCount,
                    direction: .descending
                )
            )
        )

        #expect(ascending.count == 401)
        #expect(descending.count == 401)
        #expect(ascending.map(\.id) == expectedOrder(ascending, direction: .ascending))
        #expect(descending.map(\.id) == expectedOrder(descending, direction: .descending))
        #expect(Set(ascending.map(\.id)).count == 401)
        #expect(Set(descending.map(\.id)).count == 401)
    }

    @Test("Relationship-backed sorts remain paged and stable")
    func relationshipBackedSorting() async throws {
        let fixture = try makeLargeRelationshipFixture()
        let repository = LibraryRepository(modelContainer: fixture.container)

        let albumSorted = try await allTracks(
            repository: repository,
            query: LibraryTrackQuery(
                sort: LibraryTrackSort(
                    field: .album,
                    direction: .descending
                )
            )
        )
        let yearSorted = try await allTracks(
            repository: repository,
            query: LibraryTrackQuery(
                sort: LibraryTrackSort(
                    field: .year,
                    direction: .ascending
                )
            )
        )
        let stableOrder = albumSorted.map(\.id).sorted {
            $0.uuidString < $1.uuidString
        }

        #expect(albumSorted.count == 401)
        #expect(yearSorted.count == 401)
        #expect(albumSorted.map(\.id) == stableOrder)
        #expect(yearSorted.map(\.id) == stableOrder)
    }

    @Test("Scoped relationship pages do not depend on global first pages")
    func scopedRelationshipPaging() async throws {
        let fixture = try makeLargeRelationshipFixture()
        let repository = LibraryRepository(modelContainer: fixture.container)

        let globalAlbums = try await repository.albumsPage()
        #expect(globalAlbums.items.count == 200)
        #expect(
            globalAlbums.items.allSatisfy {
                $0.artistID != fixture.artistID
            }
        )

        let artistAlbums = try await allAlbums(
            repository: repository,
            artistID: fixture.artistID
        )
        #expect(artistAlbums.count == 205)
        #expect(Set(artistAlbums.map(\.id)).count == 205)

        let albumTracks = try await allTracks(
            repository: repository,
            query: LibraryTrackQuery(scope: .album(fixture.albumID))
        )
        #expect(albumTracks.count == 401)
        #expect(Set(albumTracks.map(\.id)).count == 401)
        #expect(albumTracks.allSatisfy { $0.albumID == fixture.albumID })
    }

    @MainActor
    @Test("Production browser store pages selected relationships independently")
    func browserStoreRelationshipPaging() async throws {
        let fixture = try makeLargeRelationshipFixture()
        let store = LibraryStore(container: fixture.container)

        await store.browseAlbums(artistID: fixture.artistID)
        #expect(store.browserAlbums.count == 200)
        #expect(store.canLoadMoreBrowserAlbums)

        await store.loadNextBrowserAlbums()
        #expect(store.browserAlbums.count == 205)
        #expect(!store.canLoadMoreBrowserAlbums)

        await store.browseTracks(albumID: fixture.albumID)
        #expect(store.browserTracks.count == 200)
        #expect(store.canLoadMoreBrowserTracks)

        await store.loadNextBrowserTracks()
        await store.loadNextBrowserTracks()
        #expect(store.browserTracks.count == 401)
        #expect(!store.canLoadMoreBrowserTracks)
        #expect(Set(store.browserTracks.map(\.id)).count == 401)
    }
}

private extension CatalogPagingTests {
    func allTracks(
        repository: LibraryRepository,
        query: LibraryTrackQuery
    ) async throws -> [LibraryTrackProjection] {
        var results: [LibraryTrackProjection] = []
        var cursor: LibraryPageCursor?
        repeat {
            let page = try await repository.tracksPage(
                query: query,
                after: cursor
            )
            results.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return results
    }

    func allAlbums(
        repository: LibraryRepository,
        artistID: UUID
    ) async throws -> [LibraryAlbumProjection] {
        var results: [LibraryAlbumProjection] = []
        var cursor: LibraryPageCursor?
        repeat {
            let page = try await repository.albumsPage(
                artistID: artistID,
                after: cursor
            )
            results.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return results
    }

    func expectedOrder(
        _ tracks: [LibraryTrackProjection],
        direction: LibraryTrackSortDirection
    ) -> [UUID] {
        tracks.sorted { lhs, rhs in
            if lhs.playCount == rhs.playCount {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return direction == .ascending
                ? lhs.playCount < rhs.playCount
                : lhs.playCount > rhs.playCount
        }
        .map(\.id)
    }

    func makeLargeRelationshipFixture() throws -> LargeRelationshipFixture {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let importID = UUID()
        let session = ImportSessionRecord(
            id: importID,
            sourceDisplayName: "Large Fixture",
            state: .complete,
            importedCount: 401
        )
        let decoyArtist = ArtistRecord(
            name: "AAA Decoy Artist",
            albumCount: 200
        )
        let artist = ArtistRecord(
            name: "Target Artist",
            trackCount: 401,
            albumCount: 205
        )
        context.insert(session)
        context.insert(decoyArtist)
        context.insert(artist)
        insertDecoyAlbums(context: context, artist: decoyArtist)
        let album = try insertTargetAlbums(context: context, artist: artist)
        insertTracks(
            context: context,
            importID: importID,
            artist: artist,
            album: album
        )

        try context.save()
        return LargeRelationshipFixture(
            container: container,
            artistID: artist.id,
            albumID: album.id
        )
    }

    func insertDecoyAlbums(
        context: ModelContext,
        artist: ArtistRecord
    ) {
        for index in 0 ..< 200 {
            context.insert(
                AlbumRecord(
                    title: String(format: "AAA Album %03d", index),
                    artist: artist
                )
            )
        }
    }

    func insertTargetAlbums(
        context: ModelContext,
        artist: ArtistRecord
    ) throws -> AlbumRecord {
        var targetAlbum: AlbumRecord?
        for index in 0 ..< 205 {
            let album = AlbumRecord(
                title: String(format: "Target Album %03d", index),
                artist: artist,
                trackCount: index == 204 ? 401 : 0
            )
            context.insert(album)
            if index == 204 {
                targetAlbum = album
            }
        }
        return try #require(targetAlbum)
    }

    func insertTracks(
        context: ModelContext,
        importID: UUID,
        artist: ArtistRecord,
        album: AlbumRecord
    ) {
        for index in 0 ..< 401 {
            let id = deterministicUUID(index)
            let title = String(format: "Track %03d", index)
            context.insert(
                TrackRecord(
                    id: id,
                    originalFilename: "\(title).flac",
                    title: title,
                    duration: 120 + Double(index % 11),
                    codec: "FLAC",
                    container: "FLAC",
                    sampleRate: 48000,
                    channelCount: 2,
                    contentHash: String(format: "%064x", index + 1),
                    relativeMediaPath: "Media/\(id.uuidString).flac",
                    importSessionID: importID,
                    artist: artist,
                    album: album,
                    dateAdded: Date(timeIntervalSince1970: Double(index)),
                    playCount: index % 7
                )
            )
        }
    }

    func deterministicUUID(_ index: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                index + 1
            )
        ) ?? UUID()
    }
}

private struct LargeRelationshipFixture {
    let container: ModelContainer
    let artistID: UUID
    let albumID: UUID
}
