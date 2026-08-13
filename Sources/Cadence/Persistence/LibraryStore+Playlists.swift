import Foundation

struct LibraryPlaylistClient: Sendable {
    let playlists: @Sendable () async throws -> [LibraryPlaylistProjection]
    let playlistTracks: @Sendable (UUID) async throws -> [LibraryTrackProjection]
    let create: @Sendable (String) async throws -> LibraryPlaylistProjection
    let rename: @Sendable (UUID, String) async throws -> Void
    let delete: @Sendable (UUID) async throws -> Void
    let add: @Sendable (UUID, [UUID]) async throws -> Void
    let remove: @Sendable (UUID, [UUID]) async throws -> Void
    let reorder: @Sendable (UUID, [UUID]) async throws -> Void
    let albumTrackIDs: @Sendable (UUID) async throws -> [UUID]
    let artistTrackIDs: @Sendable (UUID) async throws -> [UUID]

    init(
        playlists: @escaping @Sendable () async throws -> [LibraryPlaylistProjection],
        playlistTracks: @escaping @Sendable (UUID) async throws -> [LibraryTrackProjection],
        create: @escaping @Sendable (String) async throws -> LibraryPlaylistProjection,
        rename: @escaping @Sendable (UUID, String) async throws -> Void,
        delete: @escaping @Sendable (UUID) async throws -> Void,
        add: @escaping @Sendable (UUID, [UUID]) async throws -> Void,
        remove: @escaping @Sendable (UUID, [UUID]) async throws -> Void,
        reorder: @escaping @Sendable (UUID, [UUID]) async throws -> Void,
        albumTrackIDs: @escaping @Sendable (UUID) async throws -> [UUID],
        artistTrackIDs: @escaping @Sendable (UUID) async throws -> [UUID]
    ) {
        self.playlists = playlists
        self.playlistTracks = playlistTracks
        self.create = create
        self.rename = rename
        self.delete = delete
        self.add = add
        self.remove = remove
        self.reorder = reorder
        self.albumTrackIDs = albumTrackIDs
        self.artistTrackIDs = artistTrackIDs
    }

    init(repository: LibraryRepository) {
        playlists = { try await repository.playlists() }
        playlistTracks = { try await repository.playlistTracks(playlistID: $0) }
        create = { try await repository.createPlaylist(name: $0) }
        rename = { try await repository.renamePlaylist(id: $0, name: $1) }
        delete = { try await repository.deletePlaylist(id: $0) }
        add = { try await repository.addToPlaylist(playlistID: $0, trackIDs: $1) }
        remove = {
            try await repository.removeFromPlaylist(
                playlistID: $0,
                trackIDs: $1
            )
        }
        reorder = {
            try await repository.reorderPlaylist(
                playlistID: $0,
                orderedTrackIDs: $1
            )
        }
        albumTrackIDs = { try await repository.playlistTrackIDs(albumID: $0) }
        artistTrackIDs = { try await repository.playlistTrackIDs(artistID: $0) }
    }
}

extension LibraryStore {
    func loadPlaylists() async {
        guard let playlistClient else {
            playlists = []
            selectedPlaylistID = nil
            selectedPlaylistTracks = []
            playlistListState = .ready
            selectedPlaylistTracksState = .ready
            return
        }

        playlistListState = .loading
        do {
            let loadedPlaylists = try await playlistClient.playlists()
            playlists = loadedPlaylists
            playlistListState = .ready
            if let selectedPlaylistID,
               !loadedPlaylists.contains(where: { $0.id == selectedPlaylistID }) {
                self.selectedPlaylistID = loadedPlaylists.first?.id
            } else if selectedPlaylistID == nil {
                selectedPlaylistID = loadedPlaylists.first?.id
            }
            await loadSelectedPlaylistTracks()
        } catch {
            let failure = LibraryStoreFailure(message: error.localizedDescription)
            playlistListState = .failed(failure)
            recordOperationFailure(.playlistList, error: error)
        }
    }

    func createPlaylist(name: String = "Untitled Playlist") async {
        guard let playlistClient else {
            return
        }
        do {
            let playlist = try await playlistClient.create(name)
            selectedPlaylistID = playlist.id
            await loadPlaylists()
        } catch {
            recordOperationFailure(.playlistCreate, error: error)
        }
    }

    func renameSelectedPlaylist(to name: String) async {
        guard let playlistClient, let selectedPlaylistID else {
            return
        }
        do {
            try await playlistClient.rename(selectedPlaylistID, name)
            await loadPlaylists()
        } catch {
            recordOperationFailure(.playlistRename, error: error)
        }
    }

    func deleteSelectedPlaylist() async {
        guard let playlistClient, let selectedPlaylistID else {
            return
        }
        do {
            try await playlistClient.delete(selectedPlaylistID)
            self.selectedPlaylistID = nil
            await loadPlaylists()
        } catch {
            recordOperationFailure(.playlistDelete, error: error)
        }
    }

    func selectPlaylist(_ id: UUID) async {
        selectedPlaylistID = id
        await loadSelectedPlaylistTracks()
    }

    func addToPlaylist(playlistID: UUID, trackIDs: [UUID]) async {
        guard let playlistClient else {
            return
        }
        do {
            try await playlistClient.add(playlistID, trackIDs)
            await loadPlaylists()
        } catch {
            recordOperationFailure(.playlistAdd, error: error)
        }
    }

    func removeFromSelectedPlaylist(trackIDs: [UUID]) async {
        guard let playlistClient, let selectedPlaylistID else {
            return
        }
        do {
            try await playlistClient.remove(selectedPlaylistID, trackIDs)
            await loadPlaylists()
        } catch {
            recordOperationFailure(.playlistRemove, error: error)
        }
    }

    func reorderSelectedPlaylist(trackIDs: [UUID]) async {
        guard let playlistClient, let selectedPlaylistID else {
            return
        }
        do {
            try await playlistClient.reorder(selectedPlaylistID, trackIDs)
            await loadSelectedPlaylistTracks()
        } catch {
            recordOperationFailure(.playlistReorder, error: error)
        }
    }

    func loadSelectedPlaylistTracks() async {
        guard let playlistClient, let selectedPlaylistID else {
            selectedPlaylistTracks = []
            selectedPlaylistTracksState = .ready
            return
        }

        selectedPlaylistTracksState = .loading
        do {
            selectedPlaylistTracks = try await playlistClient.playlistTracks(
                selectedPlaylistID
            )
            selectedPlaylistTracksState = .ready
        } catch {
            let failure = LibraryStoreFailure(message: error.localizedDescription)
            selectedPlaylistTracksState = .failed(failure)
            recordOperationFailure(.playlistTracks, error: error)
        }
    }

    func addAlbum(_ albumID: UUID, to playlistID: UUID) async {
        guard let playlistClient else {
            return
        }
        do {
            let trackIDs = try await playlistClient.albumTrackIDs(albumID)
            try await playlistClient.add(playlistID, trackIDs)
            await loadPlaylists()
        } catch {
            recordOperationFailure(.playlistAdd, error: error)
        }
    }

    func addArtist(_ artistID: UUID, to playlistID: UUID) async {
        guard let playlistClient else {
            return
        }
        do {
            let trackIDs = try await playlistClient.artistTrackIDs(artistID)
            try await playlistClient.add(playlistID, trackIDs)
            await loadPlaylists()
        } catch {
            recordOperationFailure(.playlistAdd, error: error)
        }
    }
}
