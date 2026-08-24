@testable import Cadence
import Foundation
import SwiftData
import Testing

@MainActor
struct LibraryCatalogSearchPublicationTests {
    @Test("Semantic refresh reloads a facet-only catalog search")
    func facetOnlySearchReloadsAfterSemanticMutation() async throws {
        let fixture = try FacetOnlyCatalogSearchFixture()
        defer { fixture.remove() }
        let store = LibraryStore(container: fixture.container)
        let query = "  FaCeT  "

        await store.loadInitialLibrary()
        await store.searchCatalog(query)

        #expect(SearchNormalizer.normalize(query) == "facet")
        #expect(store.catalogSearchResults.tracks.isEmpty)
        #expect(store.catalogSearchResults.albums.map(\.id) == [fixture.albumID])
        #expect(store.catalogSearchResults.artists.map(\.id) == [fixture.artistID])
        #expect(store.catalogSearchResults.tags.map(\.id) == [fixture.tagID])

        try await store.moveToTrash(
            targetKind: .album,
            targetID: fixture.albumID,
            location: fixture.location
        )

        let repository = try #require(store.repository)
        let authoritativeResults = try await repository.catalogSearch(
            query: query
        )
        #expect(authoritativeResults.tracks.isEmpty)
        #expect(authoritativeResults.albums.isEmpty)
        #expect(authoritativeResults.artists.isEmpty)
        #expect(authoritativeResults.tags.map(\.id) == [fixture.tagID])
        #expect(store.catalogSearchQuery == query)
        #expect(store.catalogSearchResults == authoritativeResults)
    }

    @Test("A stale catalog-search result cannot replace reattached results")
    func staleSearchResultCannotAffectReattachedLibrary() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let staleResults = try await libraryA.repository.catalogSearch(
            query: "Library A"
        )
        let gate = LibraryEpochResultGate(
            Result<CatalogSearchResults, LibraryEpochTestError>.success(
                staleResults
            )
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository)

        let staleSearch = Task { @MainActor in
            await store.searchCatalog(
                "Library A",
                loader: { _, _ in
                    try await gate.suspend().get()
                }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        let currentResults = try await libraryB.repository.catalogSearch(
            query: "Library B"
        )
        store.replaceCatalogSearchResults(with: currentResults)

        await gate.resume()
        await staleSearch.value

        #expect(store.repository === libraryB.repository)
        #expect(store.tracks.map(\.title) == ["Library B"])
        #expect(store.catalogSearchResults == currentResults)
        #expect(store.operationFailure == nil)
    }

    @Test("A stale catalog-search error cannot fail a reattached library")
    func staleSearchErrorCannotAffectReattachedLibrary() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let gate = LibraryEpochResultGate(
            Result<CatalogSearchResults, LibraryEpochTestError>.failure(
                .staleOperation
            )
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository)

        let staleSearch = Task { @MainActor in
            await store.searchCatalog(
                "Library A",
                loader: { _, _ in
                    try await gate.suspend().get()
                }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        let currentResults = try await libraryB.repository.catalogSearch(
            query: "Library B"
        )
        store.replaceCatalogSearchResults(with: currentResults)

        await gate.resume()
        await staleSearch.value

        #expect(store.repository === libraryB.repository)
        #expect(store.tracks.map(\.title) == ["Library B"])
        #expect(store.catalogSearchResults == currentResults)
        #expect(store.operationFailure == nil)
    }
}

private struct FacetOnlyCatalogSearchFixture {
    private struct Seed {
        let artistID: UUID
        let albumID: UUID
        let tagID: UUID
        let mediaPath: String
    }

    let root: URL
    let location: ManagedLibraryLocation
    let container: ModelContainer
    let artistID: UUID
    let albumID: UUID
    let tagID: UUID

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Facet-Search-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        location = ManagedLibraryLocation(musicDirectory: root)
        try ManagedLibraryPackage(location: location)
            .bootstrapForConfirmedImport()
        container = try LibraryContainerFactory.inMemory()
        let seed = try Self.seed(container: container)
        try Data("audio".utf8).write(
            to: location.resolve(relativePath: seed.mediaPath)
        )

        artistID = seed.artistID
        albumID = seed.albumID
        tagID = seed.tagID
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func seed(container: ModelContainer) throws -> Seed {
        let context = ModelContext(container)
        let artist = ArtistRecord(
            name: "Facet Artist",
            trackCount: 1,
            albumCount: 1
        )
        let album = AlbumRecord(
            title: "Facet Album",
            artist: artist,
            trackCount: 1,
            totalDuration: 180
        )
        let tag = TagRecord(displayPath: "facet/keep")
        let session = ImportSessionRecord(
            sourceDisplayName: "Facet Search",
            state: .complete,
            importedCount: 1
        )
        let (track, mediaPath) = makeTrack(
            artist: artist,
            album: album,
            sessionID: session.id
        )
        context.insert(artist)
        context.insert(album)
        context.insert(tag)
        context.insert(session)
        context.insert(track)
        context.insert(
            TagAssignmentRecord(
                targetKind: .album,
                targetID: album.id,
                tagID: tag.id
            )
        )
        try context.save()
        return Seed(
            artistID: artist.id,
            albumID: album.id,
            tagID: tag.id,
            mediaPath: mediaPath
        )
    }

    private static func makeTrack(
        artist: ArtistRecord,
        album: AlbumRecord,
        sessionID: UUID
    ) -> (TrackRecord, String) {
        let trackID = UUID()
        let mediaPath = "Media/\(trackID.uuidString).flac"
        return (
            TrackRecord(
                id: trackID,
                originalFilename: "Unrelated Track.flac",
                title: "Unrelated Track",
                duration: 180,
                codec: "FLAC",
                container: "FLAC",
                sampleRate: 48000,
                channelCount: 2,
                contentHash: String(repeating: "f", count: 64),
                relativeMediaPath: mediaPath,
                importSessionID: sessionID,
                artist: artist,
                album: album
            ),
            mediaPath
        )
    }
}
