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

    @Test("Detaching releases the repository and clears every published catalog")
    func detachStore() async throws {
        let container = try makeContainer(titles: ["Existing Track"])
        let store = LibraryStore(container: container)
        await store.loadInitialLibrary()

        #expect(store.repository != nil)
        #expect(!store.tracks.isEmpty)
        #expect(!store.artists.isEmpty)
        #expect(!store.albums.isEmpty)

        try await store.detach()

        #expect(store.repository == nil)
        #expect(store.availability == .empty)
        #expect(store.tracks.isEmpty)
        #expect(store.recentlyPlayedTracks.isEmpty)
        #expect(store.artists.isEmpty)
        #expect(store.albums.isEmpty)
        #expect(store.playlists.isEmpty)
        #expect(store.playbackQueueTracks.isEmpty)
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

    @Test("Concurrent next-page requests are coalesced")
    func concurrentPagedLoading() async throws {
        let container = try makeContainer(trackCount: 401)
        let repository = LibraryRepository(modelContainer: container)
        let store = LibraryStore { query, cursor in
            try await Task.sleep(for: .milliseconds(30))
            return try await repository.tracksPage(
                query: query,
                after: cursor
            )
        }

        await store.loadInitialTracks()
        async let firstLoad: Void = store.loadNextTracks()
        async let duplicateLoad: Void = store.loadNextTracks()
        _ = await (firstLoad, duplicateLoad)

        #expect(store.tracks.count == 400)
        #expect(store.canLoadMoreTracks)

        await store.loadNextTracks()
        #expect(store.tracks.count == 401)
        #expect(!store.canLoadMoreTracks)
        #expect(Set(store.tracks.map(\.id)).count == 401)
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

    @Test("Queue projections load only the current track and five upcoming tracks")
    func independentQueueProjection() async throws {
        let container = try makeContainer(trackCount: 401)
        let context = ModelContext(container)
        let requestedIDs = try context.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [SortDescriptor(\.normalizedTitle, order: .reverse)]
            )
        ).map(\.id)
        let store = LibraryStore(container: container)

        #expect(store.tracks.isEmpty)
        await store.loadPlaybackQueueTracks(ids: requestedIDs)

        #expect(store.tracks.isEmpty)
        #expect(
            store.playbackQueueTracks.map(\.id)
                == Array(requestedIDs.prefix(6))
        )
        #expect(store.playbackQueueTracks.count == 6)
        #expect(store.playbackQueueTracks.allSatisfy { $0.track != nil })
        #expect(!store.isLoadingPlaybackQueueTracks)
        #expect(store.playbackQueueProjectionError == nil)
    }

    @Test("A stale search response cannot replace a newer query")
    func staleSearchResponse() async throws {
        let container = try makeContainer(
            titles: ["Old Result", "New Result"]
        )
        let repository = LibraryRepository(modelContainer: container)
        let store = LibraryStore { query, cursor in
            if query.search == "old" {
                try await Task.sleep(for: .milliseconds(80))
            }
            return try await repository.tracksPage(
                query: query,
                after: cursor
            )
        }

        let staleRequest = Task { @MainActor in
            await store.searchTracks("old")
        }
        try await Task.sleep(for: .milliseconds(10))
        await store.searchTracks("new")
        await staleRequest.value

        #expect(store.searchQuery == "new")
        #expect(store.trackQuery.search == "new")
        #expect(store.tracks.map(\.title) == ["New Result"])
        #expect(store.availability == .ready)
    }
}

extension LibraryStoreTests {
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

    @Test("Recently played is persisted and projected independently of catalog paging")
    func recentlyPlayedProjection() async throws {
        let container = try makeContainer(
            titles: ["First", "Second", "Third"]
        )
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [SortDescriptor(\.normalizedTitle)]
            )
        )
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)
        records[0].lastPlayedAt = firstDate
        records[1].lastPlayedAt = secondDate
        try context.save()

        let store = LibraryStore(container: container)
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await window.configure(
            totalCount: store.catalogCounts.liveTrackCount,
            query: store.trackQuery,
            contentVersion: store.allTracksWindowContentVersion
        )

        #expect(store.recentlyPlayedTracks.map(\.title) == ["Second", "First"])

        let thirdID = records[2].id
        let newestDate = Date(timeIntervalSince1970: 300)
        let revisionBeforePlayback = window.revision
        #expect(
            await store.recordRecentlyPlayed(
                trackID: thirdID,
                at: newestDate
            )
        )

        #expect(store.recentlyPlayedTracks.first?.id == thirdID)
        #expect(store.recentlyPlayedTracks.first?.lastPlayedAt == newestDate)
        let residentIndex = try #require(window.index(ofTrackID: thirdID))
        #expect(window.track(at: residentIndex)?.lastPlayedAt == newestDate)
        #expect(window.revision == revisionBeforePlayback + 1)

        #expect(
            await store.recordRecentlyPlayed(
                trackID: thirdID,
                at: newestDate
            )
        )
        #expect(window.revision == revisionBeforePlayback + 1)
    }

    @Test("Projection publication only refreshes resident favorite rows")
    func projectionPublicationRespectsFavoritePageBoundary() async throws {
        let container = try makeContainer(trackCount: 201)
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [SortDescriptor(\.normalizedTitle)]
            )
        )
        for record in records {
            record.isFavorite = true
        }
        try context.save()

        let residentID = try #require(records.first?.id)
        let offPageID = try #require(records.last?.id)
        let store = LibraryStore(container: container)
        await store.loadInitialLibrary()

        #expect(store.favoriteTracks.count == 200)
        #expect(!store.favoriteTracks.contains { $0.id == offPageID })
        let initialCursor = try #require(store.favoriteTrackCursor)
        let initialVersion = store.favoriteTracksVersion
        let residentDate = Date(timeIntervalSince1970: 400)

        #expect(
            await store.recordRecentlyPlayed(
                trackID: residentID,
                at: residentDate
            )
        )

        #expect(
            store.favoriteTracks.first { $0.id == residentID }?.lastPlayedAt
                == residentDate
        )
        #expect(store.favoriteTracks.count == 200)
        #expect(store.favoriteTrackCursor == initialCursor)
        #expect(store.favoriteTracksVersion != initialVersion)
        let residentVersion = store.favoriteTracksVersion
        let residentIDs = store.favoriteTracks.map(\.id)

        #expect(
            await store.recordRecentlyPlayed(
                trackID: offPageID,
                at: Date(timeIntervalSince1970: 500)
            )
        )

        #expect(store.favoriteTracks.map(\.id) == residentIDs)
        #expect(store.favoriteTrackCursor == initialCursor)
        #expect(store.favoriteTracksVersion == residentVersion)
    }

    @Test("Favoriting ahead of a page boundary reloads that boundary")
    func favoriteMutationReloadsPageBoundary() async throws {
        let pagedTitles = (0 ... 200).map {
            "B \(String(format: "%03d", $0))"
        }
        let container = try makeContainer(
            titles: ["A New Favorite"] + pagedTitles
        )
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<TrackRecord>())
        let newFavorite = try #require(
            records.first { $0.title == "A New Favorite" }
        )
        for record in records where record.id != newFavorite.id {
            record.isFavorite = true
        }
        try context.save()

        let store = LibraryStore(container: container)
        await store.loadInitialLibrary()
        let initialCursor = try #require(store.favoriteTrackCursor)
        let initialVersion = store.favoriteTracksVersion

        #expect(store.favoriteTracks.count == 200)
        #expect(store.favoriteTracks.first?.title == "B 000")
        #expect(store.favoriteTracks.last?.title == "B 199")

        _ = try await store.setTrackFavorite(
            id: newFavorite.id,
            isFavorite: true
        )

        #expect(store.favoriteTracks.count == 200)
        #expect(store.favoriteTracks.first?.title == "A New Favorite")
        #expect(store.favoriteTracks.last?.title == "B 198")
        #expect(store.favoriteTrackCursor != initialCursor)
        #expect(store.favoriteTracksVersion != initialVersion)
        #expect(store.favoriteTrackIDs.count == 202)

        await store.loadNextFavoriteTracks()

        #expect(store.favoriteTracks.count == 202)
        #expect(Set(store.favoriteTracks.map(\.id)).count == 202)
        #expect(store.favoriteTrackCursor == nil)
    }

    @Test("Favorite catalog stays coherent when tracks, albums, and artists change")
    func favoriteCatalogMutations() async throws {
        let container = try makeContainer(titles: ["First", "Second"])
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<TrackRecord>(
                sortBy: [SortDescriptor(\.normalizedTitle)]
            )
        )
        let artist = try #require(records.first?.artist)
        let album = try #require(records.first?.album)
        records[0].isFavorite = true
        album.isFavorite = true
        album.favoriteDate = .now
        artist.isFavorite = true
        artist.favoriteDate = .now
        try context.save()

        let store = LibraryStore(container: container)
        await store.loadInitialLibrary()

        #expect(store.favoriteTracks.map(\.title) == ["First"])
        #expect(store.favoriteAlbums.map(\.title) == ["Store Album"])
        #expect(store.favoriteArtists.map(\.name) == ["Store Artist"])
        #expect(store.isTrackFavorite(records[0].id))
        #expect(!store.isTrackFavorite(records[1].id))

        _ = try await store.setTrackFavorite(
            id: records[1].id,
            isFavorite: true
        )
        #expect(store.favoriteTracks.map(\.title) == ["First", "Second"])
        #expect(store.isTrackFavorite(records[1].id))

        _ = try await store.setTrackFavorite(
            id: records[0].id,
            isFavorite: false
        )
        _ = try await store.setAlbumFavorite(
            id: album.id,
            isFavorite: false
        )
        _ = try await store.setArtistFavorite(
            id: artist.id,
            isFavorite: false
        )

        #expect(store.favoriteTracks.map(\.title) == ["Second"])
        #expect(store.favoriteAlbums.isEmpty)
        #expect(store.favoriteArtists.isEmpty)
        #expect(!store.isTrackFavorite(records[0].id))
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
