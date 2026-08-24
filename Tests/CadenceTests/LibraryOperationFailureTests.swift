@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibraryOperationFailureTests {
    @Test("Store modes make unavailable and production repositories explicit")
    func repositoryModesAreExplicit() throws {
        let unavailable = LibraryStore()
        #expect(unavailable.mode == .unavailable)

        let container = try LibraryContainerFactory.inMemory()
        let production = LibraryStore(container: container)
        #expect(production.mode == .production)
    }

    @Test("Unavailable tag operations fail instead of returning empty success")
    func unavailableTagOperationsFail() async {
        let store = LibraryStore()
        let tagID = UUID()
        let trackID = UUID()

        await #expect(throws: LibraryStoreAccessError.repositoryUnavailable) {
            try await store.tracksForTagPicker()
        }
        await #expect(throws: LibraryStoreAccessError.repositoryUnavailable) {
            try await store.tagStates(trackID: trackID)
        }
        await #expect(throws: LibraryStoreAccessError.repositoryUnavailable) {
            try await store.assignTag(tagID, trackIDs: [trackID])
        }
    }

    @Test("Quick tag and Now Playing helpers publish operation failures")
    func tagPresentationFailuresArePublished() async {
        let store = LibraryStore()
        let tagID = UUID()
        let trackID = UUID()

        await store.assignTagReportingFailure(tagID, trackIDs: [trackID])
        #expect(store.operationFailure?.operation == .tagMutation)

        store.dismissOperationFailure()
        let states = await store.tagStatesReportingFailure(trackID: trackID)
        #expect(states == nil)
        #expect(store.operationFailure?.operation == .tagLoad)
    }

    @Test("Lyrics absence and service failure remain distinct")
    func unavailableLyricsServiceThrows() async {
        let store = LibraryStore()

        await #expect(throws: ManagedLyricsServiceError.unavailable) {
            try await store.lyricsDocument(trackID: UUID())
        }
    }

    @Test("Artwork editing cannot hide a failed owner snapshot")
    func artworkSnapshotFailurePropagates() async throws {
        let container = try LibraryContainerFactory.inMemory()
        let repository = LibraryRepository(modelContainer: container)
        let location = ManagedLibraryLocation(
            musicDirectory: FileManager.default.temporaryDirectory
        )
        let store = LibraryStore()
        store.artworkService = ManagedArtworkService(
            package: ManagedLibraryPackage(location: location),
            repository: repository
        )
        let request = ManagedArtworkEditRequest(
            ownerKind: .album,
            ownerID: UUID(),
            data: Data(),
            scale: 1,
            normalizedOffset: .zero
        )

        await #expect(throws: LibraryStoreAccessError.repositoryUnavailable) {
            try await store.setArtwork(request, location: location)
        }
    }

    @Test("A failed replacement keeps the last valid track page")
    func failedTrackReplacementPreservesData() async {
        let seededTrack = LibraryTrackProjection(
            id: UUID(),
            title: "Still Here",
            artistID: nil,
            artist: "Artist",
            albumID: nil,
            album: "Album",
            duration: 180,
            year: 2026,
            codec: "flac",
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            isFavorite: false,
            customArtworkID: nil,
            artworkID: nil,
            relativeMediaPath: "Media/still-here.flac",
            lastPlayedAt: nil,
            hasSynchronizedLyrics: false
        )
        let loader = FailingTrackPageLoader(track: seededTrack)
        let store = LibraryStore { query, cursor in
            try await loader.load(query: query, cursor: cursor)
        }

        await store.loadInitialTracks()
        await store.searchTracks("fails")

        #expect(store.tracks == [seededTrack])
        #expect(store.availability == .ready)
        #expect(store.operationFailure?.operation == .trackPage)

        await store.retryOperationFailure()

        #expect(store.tracks == [seededTrack])
        #expect(store.operationFailure == nil)
    }

    @Test("Playlist mutations report failure instead of pretending to succeed")
    func playlistMutationFailuresAreExplicit() async {
        let playlistID = UUID()
        let trackID = UUID()

        let createStore = LibraryStore(
            playlistClient: .failing(at: .create)
        )
        await createStore.createPlaylist(name: "Road Trip")
        #expect(createStore.operationFailure?.operation == .playlistCreate)

        let renameStore = LibraryStore(
            playlistClient: .failing(at: .rename)
        )
        renameStore.selectedPlaylistID = playlistID
        await renameStore.renameSelectedPlaylist(to: "Night Drive")
        #expect(renameStore.operationFailure?.operation == .playlistRename)

        let deleteStore = LibraryStore(
            playlistClient: .failing(at: .delete)
        )
        deleteStore.selectedPlaylistID = playlistID
        await deleteStore.deleteSelectedPlaylist()
        #expect(deleteStore.selectedPlaylistID == playlistID)
        #expect(deleteStore.operationFailure?.operation == .playlistDelete)

        let addStore = LibraryStore(
            playlistClient: .failing(at: .add)
        )
        await addStore.addToPlaylist(
            playlistID: playlistID,
            trackIDs: [trackID]
        )
        #expect(addStore.operationFailure?.operation == .playlistAdd)

        let removeStore = LibraryStore(
            playlistClient: .failing(at: .remove)
        )
        await removeStore.selectPlaylist(playlistID)
        await removeStore.removeFromSelectedPlaylist(
            playlistID: playlistID,
            trackIDs: [trackID]
        )
        #expect(removeStore.operationFailure?.operation == .playlistRemove)

        let reorderStore = LibraryStore(
            playlistClient: .failing(at: .reorder)
        )
        await reorderStore.selectPlaylist(playlistID)
        await reorderStore.reorderSelectedPlaylist(
            playlistID: playlistID,
            trackIDs: [trackID]
        )
        #expect(reorderStore.operationFailure?.operation == .playlistReorder)
    }

    @Test("Playlist load failure preserves content and cannot look empty")
    func playlistLoadFailurePreservesContent() async {
        let playlist = LibraryPlaylistProjection(
            id: UUID(),
            name: "Keep Me",
            trackCount: 2,
            totalDuration: 360,
            modifiedAt: .now,
            customArtworkID: nil
        )
        let store = LibraryStore(
            playlistClient: .failing(at: .list)
        )
        store.playlists = [playlist]

        await store.loadPlaylists()

        #expect(store.playlists == [playlist])
        #expect(store.playlistListState.isFailure)
        #expect(store.operationFailure?.operation == .playlistList)
    }
}

@MainActor
struct PlaylistSelectionOwnershipFailureTests: PlaylistFailureTestSupport {
    @Test("A stale playlist selection cannot replace the current playlist")
    func stalePlaylistSelectionCannotPublish() async {
        let playlistA = playlist(named: "A")
        let playlistB = playlist(named: "B")
        let trackA = playlistTrack(title: "Track A")
        let trackB = playlistTrack(title: "Track B")
        let gate = PlaylistTrackLoadGate(
            suspendedPlaylistID: playlistA.id,
            suspendedResult: .success([trackA]),
            immediateTracks: [playlistB.id: [trackB]]
        )
        let commands = PlaylistCommandRecorder()
        let store = LibraryStore(
            playlistClient: playlistClient(
                playlists: [playlistA, playlistB],
                gate: gate,
                commands: commands
            )
        )
        let initialVersion = store.selectedPlaylistTracksVersion

        let staleSelection = Task { @MainActor in
            await store.selectPlaylist(playlistA.id)
        }
        await gate.waitUntilSuspended()
        await store.selectPlaylist(playlistB.id)
        let currentVersion = store.selectedPlaylistTracksVersion
        #expect(currentVersion.generation == initialVersion.generation + 1)

        await gate.resumeSuspendedRequest()
        await staleSelection.value

        #expect(store.selectedPlaylistID == playlistB.id)
        #expect(store.selectedPlaylistTracks == [trackB])
        #expect(store.selectedPlaylistTracksOwnerID == playlistB.id)
        #expect(store.selectedPlaylistTracksState == .ready)
        #expect(store.selectedPlaylistTracksVersion == currentVersion)
        #expect(store.operationFailure == nil)
        let actionTrackIDs = store.selectedPlaylistTracks.map(\.id)
        await store.removeFromSelectedPlaylist(
            playlistID: playlistB.id,
            trackIDs: actionTrackIDs
        )
        await store.reorderSelectedPlaylist(
            playlistID: playlistB.id,
            trackIDs: actionTrackIDs
        )

        #expect(
            await commands.removeContexts
                == [PlaylistCommandContext(
                    playlistID: playlistB.id,
                    trackIDs: [trackB.id]
                )]
        )
        #expect(
            await commands.reorderContexts
                == [PlaylistCommandContext(
                    playlistID: playlistB.id,
                    trackIDs: [trackB.id]
                )]
        )
        #expect(
            await gate.requestedPlaylistIDs
                == [playlistA.id, playlistB.id, playlistB.id, playlistB.id]
        )
    }

    @Test("Selecting a new playlist retires the old rows before success")
    func newPlaylistSelectionRetiresOldRowsBeforeSuccess() async {
        let playlistA = playlist(named: "A")
        let playlistB = playlist(named: "B")
        let trackA = playlistTrack(title: "Track A")
        let trackB = playlistTrack(title: "Track B")
        let gate = PlaylistTrackLoadGate(
            suspendedPlaylistID: playlistB.id,
            suspendedResult: .success([trackB]),
            immediateTracks: [playlistA.id: [trackA]]
        )
        let commands = PlaylistCommandRecorder()
        let store = LibraryStore(
            playlistClient: playlistClient(
                playlists: [playlistA, playlistB],
                gate: gate,
                commands: commands
            )
        )
        await store.selectPlaylist(playlistA.id)
        let playlistAVersion = store.selectedPlaylistTracksVersion
        let staleActionTrackIDs = store.selectedPlaylistTracks.map(\.id)
        #expect(store.selectedPlaylistTracks == [trackA])
        #expect(store.selectedPlaylistTracksOwnerID == playlistA.id)
        #expect(store.ownsSelectedPlaylistTracks(for: playlistA.id))

        let selectPlaylistB = Task { @MainActor in
            await store.selectPlaylist(playlistB.id)
        }
        await gate.waitUntilSuspended()

        #expect(store.selectedPlaylistID == playlistB.id)
        #expect(store.selectedPlaylistTracks.isEmpty)
        #expect(store.selectedPlaylistTracksOwnerID == nil)
        #expect(!store.ownsSelectedPlaylistTracks(for: playlistA.id))
        #expect(!store.ownsSelectedPlaylistTracks(for: playlistB.id))
        #expect(store.selectedPlaylistTrackSource(for: playlistB.id) == nil)
        #expect(store.selectedPlaylistTracksState == .loading)
        #expect(
            store.selectedPlaylistTracksVersion.generation
                == playlistAVersion.generation + 1
        )
        await store.removeFromSelectedPlaylist(
            playlistID: playlistA.id,
            trackIDs: staleActionTrackIDs
        )
        await store.reorderSelectedPlaylist(
            playlistID: playlistA.id,
            trackIDs: staleActionTrackIDs
        )
        #expect(await commands.removeContexts.isEmpty)
        #expect(await commands.reorderContexts.isEmpty)

        await gate.resumeSuspendedRequest()
        await selectPlaylistB.value

        #expect(store.selectedPlaylistTracks == [trackB])
        #expect(store.selectedPlaylistTracksOwnerID == playlistB.id)
        #expect(store.ownsSelectedPlaylistTracks(for: playlistB.id))
        #expect(
            store.selectedPlaylistTrackSource(for: playlistB.id)?.tracks
                == [trackB]
        )
        #expect(store.selectedPlaylistTracksState == .ready)
        #expect(
            store.selectedPlaylistTracksVersion.generation
                == playlistAVersion.generation + 2
        )
        await store.removeFromSelectedPlaylist(
            playlistID: playlistA.id,
            trackIDs: staleActionTrackIDs
        )
        await store.reorderSelectedPlaylist(
            playlistID: playlistA.id,
            trackIDs: staleActionTrackIDs
        )
        #expect(await commands.removeContexts.isEmpty)
        #expect(await commands.reorderContexts.isEmpty)
    }

    @Test("A failed new playlist selection cannot expose old actions")
    func failedNewPlaylistSelectionRetiresOldRowsAndActions() async {
        let playlistA = playlist(named: "A")
        let playlistB = playlist(named: "B")
        let trackA = playlistTrack(title: "Track A")
        let gate = PlaylistTrackLoadGate(
            suspendedPlaylistID: playlistB.id,
            suspendedResult: .failure(PlaylistOwnershipFailure.stale),
            immediateTracks: [playlistA.id: [trackA]]
        )
        let commands = PlaylistCommandRecorder()
        let store = LibraryStore(
            playlistClient: playlistClient(
                playlists: [playlistA, playlistB],
                gate: gate,
                commands: commands
            )
        )
        await store.selectPlaylist(playlistA.id)
        let playlistAVersion = store.selectedPlaylistTracksVersion
        let staleActionTrackIDs = store.selectedPlaylistTracks.map(\.id)
        #expect(store.selectedPlaylistTracks == [trackA])
        #expect(store.selectedPlaylistTracksOwnerID == playlistA.id)

        let selectPlaylistB = Task { @MainActor in
            await store.selectPlaylist(playlistB.id)
        }
        await gate.waitUntilSuspended()

        #expect(store.selectedPlaylistID == playlistB.id)
        #expect(store.selectedPlaylistTracks.isEmpty)
        #expect(store.selectedPlaylistTracksOwnerID == nil)
        #expect(!store.ownsSelectedPlaylistTracks(for: playlistB.id))
        #expect(store.selectedPlaylistTrackSource(for: playlistB.id) == nil)
        #expect(store.selectedPlaylistTracksState == .loading)
        #expect(
            store.selectedPlaylistTracksVersion.generation
                == playlistAVersion.generation + 1
        )

        await gate.resumeSuspendedRequest()
        await selectPlaylistB.value

        #expect(store.selectedPlaylistTracks.isEmpty)
        #expect(store.selectedPlaylistTracksOwnerID == nil)
        #expect(!store.ownsSelectedPlaylistTracks(for: playlistB.id))
        #expect(store.selectedPlaylistTrackSource(for: playlistB.id) == nil)
        #expect(store.selectedPlaylistTracksState.isFailure)
        #expect(
            store.selectedPlaylistTracksVersion.generation
                == playlistAVersion.generation + 1
        )
        await store.removeFromSelectedPlaylist(
            playlistID: playlistB.id,
            trackIDs: staleActionTrackIDs
        )
        await store.reorderSelectedPlaylist(
            playlistID: playlistB.id,
            trackIDs: staleActionTrackIDs
        )
        #expect(await commands.removeContexts.isEmpty)
        #expect(await commands.reorderContexts.isEmpty)
    }

    @Test("A stale playlist failure cannot fail the current playlist")
    func stalePlaylistFailureCannotPublish() async {
        let playlistA = playlist(named: "A")
        let playlistB = playlist(named: "B")
        let trackB = playlistTrack(title: "Track B")
        let gate = PlaylistTrackLoadGate(
            suspendedPlaylistID: playlistA.id,
            suspendedResult: .failure(PlaylistOwnershipFailure.stale),
            immediateTracks: [playlistB.id: [trackB]]
        )
        let store = LibraryStore(
            playlistClient: playlistClient(
                playlists: [playlistA, playlistB],
                gate: gate
            )
        )
        let initialVersion = store.selectedPlaylistTracksVersion

        let staleSelection = Task { @MainActor in
            await store.selectPlaylist(playlistA.id)
        }
        await gate.waitUntilSuspended()
        await store.selectPlaylist(playlistB.id)
        let currentVersion = store.selectedPlaylistTracksVersion
        #expect(currentVersion.generation == initialVersion.generation + 1)

        await gate.resumeSuspendedRequest()
        await staleSelection.value

        #expect(store.selectedPlaylistID == playlistB.id)
        #expect(store.selectedPlaylistTracks == [trackB])
        #expect(store.selectedPlaylistTracksOwnerID == playlistB.id)
        #expect(store.selectedPlaylistTracksState == .ready)
        #expect(store.selectedPlaylistTracksVersion == currentVersion)
        #expect(store.operationFailure == nil)
    }
}

@MainActor
struct PlaylistMutationRaceFailureTests: PlaylistFailureTestSupport {
    @Test("The newest same-playlist refresh owns playlist content")
    func newestSamePlaylistRefreshOwnsContent() async {
        let playlist = playlist(named: "A")
        let staleTrack = playlistTrack(title: "Stale")
        let currentTrack = playlistTrack(title: "Current")
        let gate = PlaylistTrackLoadGate(
            suspendedPlaylistID: playlist.id,
            suspendedResult: .success([staleTrack]),
            immediateTracks: [playlist.id: [currentTrack]]
        )
        let store = LibraryStore(
            playlistClient: playlistClient(
                playlists: [playlist],
                gate: gate
            )
        )
        let initialVersion = store.selectedPlaylistTracksVersion

        let staleRefresh = Task { @MainActor in
            await store.selectPlaylist(playlist.id)
        }
        await gate.waitUntilSuspended()
        await store.selectPlaylist(playlist.id)
        let currentVersion = store.selectedPlaylistTracksVersion
        #expect(currentVersion.generation == initialVersion.generation + 1)

        await gate.resumeSuspendedRequest()
        await staleRefresh.value

        #expect(store.selectedPlaylistID == playlist.id)
        #expect(store.selectedPlaylistTracks == [currentTrack])
        #expect(store.selectedPlaylistTracksOwnerID == playlist.id)
        #expect(store.selectedPlaylistTracksState == .ready)
        #expect(store.selectedPlaylistTracksVersion == currentVersion)
        #expect(store.operationFailure == nil)
        #expect(await gate.requestedPlaylistIDs == [playlist.id, playlist.id])
    }

    @Test("A stale reorder cannot start loading the newly selected playlist")
    func staleReorderCannotReloadNewSelection() async {
        let playlistA = playlist(named: "A")
        let playlistB = playlist(named: "B")
        let trackB = playlistTrack(title: "Track B")
        let gate = PlaylistTrackLoadGate(
            suspendedPlaylistID: UUID(),
            suspendedResult: .success([]),
            immediateTracks: [playlistB.id: [trackB]]
        )
        let commands = PlaylistCommandRecorder(suspendsReorder: true)
        let store = LibraryStore(
            playlistClient: playlistClient(
                playlists: [playlistA, playlistB],
                gate: gate,
                commands: commands
            )
        )
        await store.selectPlaylist(playlistA.id)
        #expect(store.selectedPlaylistTracksOwnerID == playlistA.id)

        let staleReorder = Task { @MainActor in
            await store.reorderSelectedPlaylist(
                playlistID: playlistA.id,
                trackIDs: [UUID()]
            )
        }
        await commands.waitUntilReorderSuspended()
        await store.selectPlaylist(playlistB.id)
        let currentVersion = store.selectedPlaylistTracksVersion

        await commands.resumeReorder()
        await staleReorder.value

        #expect(store.selectedPlaylistID == playlistB.id)
        #expect(store.selectedPlaylistTracks == [trackB])
        #expect(store.selectedPlaylistTracksState == .ready)
        #expect(store.selectedPlaylistTracksVersion == currentVersion)
        #expect(
            await gate.requestedPlaylistIDs == [playlistA.id, playlistB.id]
        )
        #expect(await commands.reorderContexts.count == 1)
        #expect(await commands.reorderContexts.first?.playlistID == playlistA.id)
    }

    @Test("A stale reorder failure cannot fail the newly selected playlist")
    func staleReorderFailureCannotFailNewSelection() async {
        let playlistA = playlist(named: "A")
        let playlistB = playlist(named: "B")
        let trackB = playlistTrack(title: "Track B")
        let gate = PlaylistTrackLoadGate(
            suspendedPlaylistID: UUID(),
            suspendedResult: .success([]),
            immediateTracks: [playlistB.id: [trackB]]
        )
        let commands = PlaylistCommandRecorder(
            suspendsReorder: true,
            failsReorder: true
        )
        let store = LibraryStore(
            playlistClient: playlistClient(
                playlists: [playlistA, playlistB],
                gate: gate,
                commands: commands
            )
        )
        await store.selectPlaylist(playlistA.id)
        #expect(store.selectedPlaylistTracksOwnerID == playlistA.id)

        let staleReorder = Task { @MainActor in
            await store.reorderSelectedPlaylist(
                playlistID: playlistA.id,
                trackIDs: [UUID()]
            )
        }
        await commands.waitUntilReorderSuspended()
        await store.selectPlaylist(playlistB.id)
        let currentVersion = store.selectedPlaylistTracksVersion

        await commands.resumeReorder()
        await staleReorder.value

        #expect(store.selectedPlaylistID == playlistB.id)
        #expect(store.selectedPlaylistTracks == [trackB])
        #expect(store.selectedPlaylistTracksState == .ready)
        #expect(store.selectedPlaylistTracksVersion == currentVersion)
        #expect(store.operationFailure == nil)
        #expect(
            await gate.requestedPlaylistIDs == [playlistA.id, playlistB.id]
        )
    }
}

@MainActor
struct CatalogLookupFailureTests {
    @Test("Catalog lookups distinguish missing content from storage failure")
    func catalogLookupFailureIsNotAnEmptyResult() async throws {
        let itemID = UUID()
        let emptyStore = LibraryStore(catalogLookupClient: .empty)

        #expect(try await emptyStore.album(id: itemID) == nil)
        #expect(try await emptyStore.artist(id: itemID) == nil)
        #expect(try await emptyStore.tracks(albumID: itemID).isEmpty)
        #expect(try await emptyStore.tracks(artistID: itemID).isEmpty)
        #expect(try await emptyStore.allTrackIDs().isEmpty)

        let failingStore = LibraryStore(catalogLookupClient: .failing)
        await #expect(throws: CatalogLookupFailure.expected) {
            try await failingStore.album(id: itemID)
        }
        await #expect(throws: CatalogLookupFailure.expected) {
            try await failingStore.artist(id: itemID)
        }
        await #expect(throws: CatalogLookupFailure.expected) {
            try await failingStore.tracks(albumID: itemID)
        }
        await #expect(throws: CatalogLookupFailure.expected) {
            try await failingStore.tracks(artistID: itemID)
        }
        await #expect(throws: CatalogLookupFailure.expected) {
            try await failingStore.allTrackIDs()
        }
    }
}

@MainActor
protocol PlaylistFailureTestSupport {}

@MainActor
private extension PlaylistFailureTestSupport {
    func playlist(named name: String) -> LibraryPlaylistProjection {
        LibraryPlaylistProjection(
            id: UUID(),
            name: name,
            trackCount: 1,
            totalDuration: 180,
            modifiedAt: Date(timeIntervalSince1970: 1),
            customArtworkID: nil
        )
    }

    func playlistTrack(title: String) -> LibraryTrackProjection {
        LibraryTrackProjection(
            id: UUID(),
            title: title,
            artistID: nil,
            artist: "Artist",
            albumID: nil,
            album: "Album",
            duration: 180,
            year: 2026,
            codec: "ALAC",
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            isFavorite: false,
            customArtworkID: nil,
            artworkID: nil,
            relativeMediaPath: "\(title).m4a",
            lastPlayedAt: nil,
            hasSynchronizedLyrics: false
        )
    }

    func playlistClient(
        playlists: [LibraryPlaylistProjection],
        gate: PlaylistTrackLoadGate,
        commands: PlaylistCommandRecorder = PlaylistCommandRecorder()
    ) -> LibraryPlaylistClient {
        LibraryPlaylistClient(
            playlists: { playlists },
            playlistTracks: { playlistID in
                try await gate.load(playlistID: playlistID)
            },
            create: { name in
                LibraryPlaylistProjection(
                    id: UUID(),
                    name: name,
                    trackCount: 0,
                    totalDuration: 0,
                    modifiedAt: Date(timeIntervalSince1970: 1),
                    customArtworkID: nil
                )
            },
            rename: { _, _ in },
            delete: { _ in },
            add: { _, _ in },
            remove: { playlistID, trackIDs in
                await commands.recordRemove(playlistID, trackIDs: trackIDs)
            },
            reorder: { playlistID, trackIDs in
                try await commands.recordReorder(
                    playlistID,
                    trackIDs: trackIDs
                )
            },
            albumTrackIDs: { _ in [] },
            artistTrackIDs: { _ in [] }
        )
    }
}

private actor PlaylistTrackLoadGate {
    private let suspendedPlaylistID: UUID
    private let suspendedResult: Result<[LibraryTrackProjection], Error>
    private let immediateTracks: [UUID: [LibraryTrackProjection]]
    private var hasSuspended = false
    private var suspendedContinuation:
        CheckedContinuation<[LibraryTrackProjection], Error>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requestedPlaylistIDs: [UUID] = []

    init(
        suspendedPlaylistID: UUID,
        suspendedResult: Result<[LibraryTrackProjection], Error>,
        immediateTracks: [UUID: [LibraryTrackProjection]]
    ) {
        self.suspendedPlaylistID = suspendedPlaylistID
        self.suspendedResult = suspendedResult
        self.immediateTracks = immediateTracks
    }

    func load(playlistID: UUID) async throws -> [LibraryTrackProjection] {
        requestedPlaylistIDs.append(playlistID)
        if playlistID == suspendedPlaylistID, !hasSuspended {
            hasSuspended = true
            suspensionWaiters.forEach { $0.resume() }
            suspensionWaiters.removeAll()
            return try await withCheckedThrowingContinuation { continuation in
                suspendedContinuation = continuation
            }
        }
        return immediateTracks[playlistID] ?? []
    }

    func waitUntilSuspended() async {
        guard !hasSuspended else {
            return
        }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resumeSuspendedRequest() {
        guard let suspendedContinuation else {
            return
        }
        self.suspendedContinuation = nil
        suspendedContinuation.resume(with: suspendedResult)
    }
}

private actor PlaylistCommandRecorder {
    private let suspendsReorder: Bool
    private let failsReorder: Bool
    private var didSuspendReorder = false
    private var reorderContinuation: CheckedContinuation<Void, Never>?
    private var reorderWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var removeContexts: [PlaylistCommandContext] = []
    private(set) var reorderContexts: [PlaylistCommandContext] = []

    init(
        suspendsReorder: Bool = false,
        failsReorder: Bool = false
    ) {
        self.suspendsReorder = suspendsReorder
        self.failsReorder = failsReorder
    }

    func recordRemove(_ playlistID: UUID, trackIDs: [UUID]) {
        removeContexts.append(
            PlaylistCommandContext(playlistID: playlistID, trackIDs: trackIDs)
        )
    }

    func recordReorder(
        _ playlistID: UUID,
        trackIDs: [UUID]
    ) async throws {
        reorderContexts.append(
            PlaylistCommandContext(playlistID: playlistID, trackIDs: trackIDs)
        )
        guard suspendsReorder, !didSuspendReorder else {
            if failsReorder {
                throw PlaylistOwnershipFailure.stale
            }
            return
        }
        didSuspendReorder = true
        reorderWaiters.forEach { $0.resume() }
        reorderWaiters.removeAll()
        await withCheckedContinuation { continuation in
            reorderContinuation = continuation
        }
        if failsReorder {
            throw PlaylistOwnershipFailure.stale
        }
    }

    func waitUntilReorderSuspended() async {
        guard !didSuspendReorder else {
            return
        }
        await withCheckedContinuation { continuation in
            reorderWaiters.append(continuation)
        }
    }

    func resumeReorder() {
        reorderContinuation?.resume()
        reorderContinuation = nil
    }
}

private struct PlaylistCommandContext: Equatable, Sendable {
    let playlistID: UUID
    let trackIDs: [UUID]
}

private enum PlaylistOwnershipFailure: Error {
    case stale
}

private extension LibraryCatalogLookupClient {
    static let empty = Self(
        artist: { _ in nil },
        album: { _ in nil },
        albumTracks: { _ in [] },
        artistTracks: { _ in [] },
        artistAlbums: { _ in [] },
        artistReleases: { _ in .empty },
        tagTracks: { _ in [] },
        allTrackIDs: { [] }
    )

    static let failing = Self(
        artist: { _ in throw CatalogLookupFailure.expected },
        album: { _ in throw CatalogLookupFailure.expected },
        albumTracks: { _ in throw CatalogLookupFailure.expected },
        artistTracks: { _ in throw CatalogLookupFailure.expected },
        artistAlbums: { _ in throw CatalogLookupFailure.expected },
        artistReleases: { _ in throw CatalogLookupFailure.expected },
        tagTracks: { _ in throw CatalogLookupFailure.expected },
        allTrackIDs: { throw CatalogLookupFailure.expected }
    )
}

private enum CatalogLookupFailure: Error {
    case expected
}

private enum PlaylistFailurePoint: Equatable {
    case list
    case tracks
    case create
    case rename
    case delete
    case add
    case remove
    case reorder
    case albumTracks
    case artistTracks
}

private extension LibraryPlaylistClient {
    static func failing(
        at failurePoint: PlaylistFailurePoint
    ) -> Self {
        Self(
            playlists: {
                try fail(.list, requested: failurePoint)
                return []
            },
            playlistTracks: { _ in
                try fail(.tracks, requested: failurePoint)
                return []
            },
            create: { _ in
                try fail(.create, requested: failurePoint)
                throw PlaylistFailure.expected
            },
            rename: { _, _ in
                try fail(.rename, requested: failurePoint)
            },
            delete: { _ in
                try fail(.delete, requested: failurePoint)
            },
            add: { _, _ in
                try fail(.add, requested: failurePoint)
            },
            remove: { _, _ in
                try fail(.remove, requested: failurePoint)
            },
            reorder: { _, _ in
                try fail(.reorder, requested: failurePoint)
            },
            albumTrackIDs: { _ in
                try fail(.albumTracks, requested: failurePoint)
                return []
            },
            artistTrackIDs: { _ in
                try fail(.artistTracks, requested: failurePoint)
                return []
            }
        )
    }

    static func fail(
        _ operation: PlaylistFailurePoint,
        requested failurePoint: PlaylistFailurePoint
    ) throws {
        if operation == failurePoint {
            throw PlaylistFailure.expected
        }
    }
}

private enum PlaylistFailure: Error {
    case expected
}

private actor FailingTrackPageLoader {
    let track: LibraryTrackProjection
    var requestCount = 0

    init(track: LibraryTrackProjection) {
        self.track = track
    }

    func load(
        query _: LibraryTrackQuery,
        cursor _: LibraryPageCursor?
    ) throws -> LibraryPage<LibraryTrackProjection> {
        requestCount += 1
        if requestCount == 2 {
            throw Failure.expected
        }
        return LibraryPage(items: [track], nextCursor: nil)
    }

    private enum Failure: Error {
        case expected
    }
}
