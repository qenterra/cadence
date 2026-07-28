@testable import Cadence
import Foundation
import SwiftData
import Testing

@MainActor
struct LibraryStoreTests {
    @Test("A store without a container is an honest empty library")
    func emptyStore() {
        let store = LibraryStore()

        #expect(store.availability == .empty)
        #expect(store.tracks.isEmpty)
        #expect(!store.canLoadMoreTracks)
    }

    @Test("Initial and next loads append bounded repository pages")
    func pagedLoading() async throws {
        let container = try makeContainer(trackCount: 205)
        let store = LibraryStore(container: container)

        await store.loadInitialTracks()
        #expect(store.availability == .ready)
        #expect(store.tracks.count == 200)
        #expect(store.canLoadMoreTracks)

        await store.loadNextTracks()
        #expect(store.tracks.count == 205)
        #expect(!store.canLoadMoreTracks)
    }

    @Test("A new search replaces prior pages instead of mixing results")
    func searchReplacement() async throws {
        let container = try makeContainer(
            titles: ["Échoes", "Midnight Static", "Echo Chamber"]
        )
        let store = LibraryStore(container: container)

        await store.loadInitialTracks()
        await store.searchTracks("echo")

        #expect(store.tracks.map(\.title) == ["Echo Chamber", "Échoes"])
        #expect(store.searchQuery == "echo")
    }

    @Test("Initial library loading publishes bounded artist, album, and track pages")
    func initialLibraryLoading() async throws {
        let container = try makeContainer(trackCount: 205)
        let store = LibraryStore(container: container)

        await store.loadInitialLibrary()

        #expect(store.availability == .ready)
        #expect(store.artists.map(\.name) == ["Store Artist"])
        #expect(store.albums.map(\.title) == ["Store Album"])
        #expect(store.tracks.count == 200)
        #expect(store.canLoadMoreTracks)
        #expect(!store.canLoadMoreArtists)
        #expect(!store.canLoadMoreAlbums)
    }

    @Test("Catalog search publishes grouped production results")
    func groupedCatalogSearch() async throws {
        let container = try makeContainer(
            titles: ["Midnight Static", "Glass Horizon"]
        )
        let store = LibraryStore(container: container)

        await store.loadInitialLibrary()
        await store.searchCatalog("store")

        #expect(store.catalogSearchQuery == "store")
        #expect(store.catalogSearchResults.artists.map(\.name) == ["Store Artist"])
        #expect(store.catalogSearchResults.albums.map(\.title) == ["Store Album"])
        #expect(!store.isCatalogSearching)

        await store.searchCatalog("")
        #expect(store.catalogSearchResults == .empty)
    }

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
        let artist = ArtistRecord(name: "Store Artist")
        let album = AlbumRecord(title: "Store Album", artist: artist)
        let session = ImportSessionRecord(
            id: importID,
            sourceDisplayName: "Fixture",
            state: .complete
        )

        context.insert(artist)
        context.insert(album)
        context.insert(session)

        for (index, title) in titles.enumerated() {
            let trackID = UUID()
            context.insert(
                TrackRecord(
                    id: trackID,
                    originalFilename: "\(title).flac",
                    title: title,
                    duration: 180,
                    codec: "FLAC",
                    container: "FLAC",
                    sampleRate: 48000,
                    channelCount: 2,
                    contentHash: String(format: "%064x", index + 1),
                    relativeMediaPath: "Media/\(trackID.uuidString).flac",
                    importSessionID: importID,
                    artist: artist,
                    album: album
                )
            )
        }

        try context.save()
        return container
    }
}
