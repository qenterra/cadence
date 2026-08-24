@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibraryStoreLifecycleEpochTests {
    @Test("Clearing search invalidates a queued catalog restoration")
    func clearingSearchInvalidatesQueuedCatalogRestoration() async throws {
        let library = try LibraryEpochFixture(title: "Library")
        let invocations = LifecycleInvocationRecorder()
        let store = LibraryStore()
        try await store.attach(repository: library.repository)

        store.restoreCatalogSearch("old query") { _, _ in
            await invocations.record()
            return .empty
        }
        store.clearCatalogSearch()
        while !store.attachmentTasks.isEmpty {
            await Task.yield()
        }

        #expect(await invocations.invocationCount == 0)
        #expect(store.catalogSearchQuery.isEmpty)
        #expect(store.catalogSearchResults == .empty)
        #expect(!store.isCatalogSearching)
        #expect(store.operationFailure == nil)
    }

    @Test("Reattachment clears observable state before the new library loads")
    func reattachmentClearsObservableStateBeforeNewLibraryLoads()
        async throws {
        let playlistID = UUID()
        let trackA = makeLifecycleTrack(title: "Track A")
        let playlistA = makeLifecyclePlaylist(
            id: playlistID,
            name: "Library A"
        )
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository)
        await seedLifecycleAttachmentState(
            in: store,
            playlist: playlistA,
            track: trackA
        )

        try await store.attach(repository: libraryB.repository)

        #expect(store.repository === libraryB.repository)
        #expect(store.playlists.isEmpty)
        #expect(store.selectedPlaylistID == nil)
        #expect(store.selectedPlaylistTracks.isEmpty)
        #expect(store.selectedPlaylistTracksState == .idle)
        #expect(store.browserArtistID == nil)
        #expect(store.browserAlbumID == nil)
        #expect(store.browserTracks.isEmpty)
        #expect(store.browserTracksState == .idle)
        #expect(store.catalogSearchQuery.isEmpty)
        #expect(store.catalogSearchResults == .empty)
        #expect(!store.isCatalogSearching)
        #expect(store.loadingCatalogSearchGroups.isEmpty)
        #expect(store.operationFailure == nil)
        #expect(store.smartCollectionSummaries.isEmpty)
        #expect(store.smartCollectionResults.isEmpty)
        #expect(store.availability == .ready)
    }

    @Test("A stale playlist mutation cannot publish into a reattached library")
    func stalePlaylistMutationCannotPublishIntoReattachedLibrary()
        async throws {
        let playlistID = UUID()
        let playlistA = makeLifecyclePlaylist(id: playlistID, name: "Library A")
        let playlistB = makeLifecyclePlaylist(id: playlistID, name: "Library B")
        let trackA = makeLifecycleTrack(title: "Track A")
        let trackB = makeLifecycleTrack(title: "Track B")
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let gate = LibraryEpochResultGate(
            Result<Void, LibraryEpochTestError>.failure(.staleOperation)
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository)
        store.playlistClient = makeLifecyclePlaylistClient(
            playlists: { [playlistA] },
            tracks: [playlistID: [trackA]],
            remove: { _, _ in try await gate.suspend().get() }
        )
        await store.loadPlaylists()
        let staleMutation = Task { @MainActor in
            await store.removeFromSelectedPlaylist(
                playlistID: playlistID,
                trackIDs: [trackA.id]
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository)
        store.playlistClient = makeLifecyclePlaylistClient(
            playlists: { [playlistB] },
            tracks: [playlistID: [trackB]]
        )
        await store.loadPlaylists()
        let currentTracksVersion = store.selectedPlaylistTracksVersion

        await gate.resume()
        await staleMutation.value

        #expect(store.repository === libraryB.repository)
        #expect(store.playlists == [playlistB])
        #expect(store.selectedPlaylistTracks == [trackB])
        #expect(store.selectedPlaylistTracksVersion == currentTracksVersion)
        #expect(store.operationFailure == nil)
    }

    @Test("A stale playlist load cannot publish into a reattached library")
    func stalePlaylistLoadCannotPublishIntoReattachedLibrary() async throws {
        let playlistID = UUID()
        let playlistA = makeLifecyclePlaylist(id: playlistID, name: "Library A")
        let playlistB = makeLifecyclePlaylist(id: playlistID, name: "Library B")
        let trackA = makeLifecycleTrack(title: "Track A")
        let trackB = makeLifecycleTrack(title: "Track B")
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let gate = LibraryEpochResultGate(
            Result<[LibraryPlaylistProjection], LibraryEpochTestError>
                .success([playlistA])
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository)
        store.playlistClient = makeLifecyclePlaylistClient(
            playlists: { try await gate.suspend().get() },
            tracks: [playlistID: [trackA]]
        )

        let staleLoad = Task { @MainActor in
            await store.loadPlaylists()
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository)
        store.playlistClient = makeLifecyclePlaylistClient(
            playlists: { [playlistB] },
            tracks: [playlistID: [trackB]]
        )
        await store.loadPlaylists()
        let currentTracksVersion = store.selectedPlaylistTracksVersion

        await gate.resume()
        await staleLoad.value

        #expect(store.repository === libraryB.repository)
        #expect(store.playlists == [playlistB])
        #expect(store.selectedPlaylistID == playlistID)
        #expect(store.selectedPlaylistTracks == [trackB])
        #expect(store.selectedPlaylistTracksOwnerID == playlistID)
        #expect(store.selectedPlaylistTracksVersion == currentTracksVersion)
        #expect(store.playlistListState == .ready)
        #expect(store.selectedPlaylistTracksState == .ready)
        #expect(store.operationFailure == nil)
    }

    @Test("Replacement cancels and joins lyrics work before closing its index")
    func replacementCancelsAndJoinsLyricsWorkBeforeClosingOldIndex()
        async throws {
        let context = try await LyricsLifecycleReplacementTestContext.make()

        let synchronization = Task { @MainActor in
            await context.store.synchronizeLyricsSearch()
        }
        await context.events.wait(for: .started)

        let replacement = Task { @MainActor in
            await context.replacementStarted.fire()
            try await context.store.attach(
                repository: context.libraryBRepository,
                lyricsSearchIndexer: context.indexerB
            )
            await context.events.record(.installedB)
        }
        await context.replacementStarted.wait()
        let firstReplacementEffect = await context.events
            .waitForCancellationOrInstallation()

        #expect(firstReplacementEffect == .cancelled)
        #expect(!context.store.isCurrentLibraryContext(context.libraryAContext))
        #expect(context.store.repository === context.libraryARepository)
        #expect(context.store.lyricsSearchIndexer === context.indexerA)

        await context.synchronizationGate.resume()
        await context.cleanupGate.resume()
        await synchronization.value
        try await replacement.value

        #expect(
            await context.events.values
                == [.started, .cancelled, .finished, .closed, .installedB]
        )
        #expect(context.store.repository === context.libraryBRepository)
        #expect(context.store.lyricsSearchIndexer === context.indexerB)
        #expect(context.store.lyricsSearchIndexState == .idle)
        #expect(context.store.operationFailure == nil)
    }

    private func seedLifecycleAttachmentState(
        in store: LibraryStore,
        playlist: LibraryPlaylistProjection,
        track: LibraryTrackProjection
    ) async {
        store.playlistClient = makeLifecyclePlaylistClient(
            playlists: { [playlist] },
            tracks: [playlist.id: [track]]
        )
        await store.loadPlaylists()
        store.browserArtistID = UUID()
        store.browserAlbumID = UUID()
        store.replaceBrowserTracksContent(with: [track])
        store.browserTracksState = .ready
        await store.searchCatalog("Library A") { _, _ in
            var results = CatalogSearchResults.empty
            results.tracks = [track]
            return results
        }
        store.loadingCatalogSearchGroups = [.tracks]
        store.recordOperationFailure(
            .playlistRemove,
            error: LibraryEpochTestError.staleOperation
        )
        let smartRule = SmartCollectionRuleGroup(
            combinator: .all,
            children: []
        )
        store.smartCollectionSummaries[smartRule] = .empty
    }
}
