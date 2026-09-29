import Foundation

struct LibraryPlaylistClient: Sendable {
    let attachmentID = UUID()
    let playlists: @Sendable () async throws -> [LibraryPlaylistProjection]
    let playlistTracks: @Sendable (UUID) async throws -> [LibraryTrackProjection]
    let create: @Sendable (String) async throws -> LibraryPlaylistProjection
    let rename: @Sendable (UUID, String) async throws -> Void
    let updateMetadata: @Sendable (UUID, String, String?) async throws -> Void
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
        updateMetadata: (@Sendable (UUID, String, String?) async throws -> Void)? = nil,
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
        self.updateMetadata = updateMetadata ?? { id, name, _ in
            try await rename(id, name)
        }
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
        updateMetadata = {
            try await repository.updatePlaylist(
                id: $0,
                name: $1,
                userDescription: $2
            )
        }
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
        let context = captureLibraryContext()
        guard attachmentPhase == .active else {
            return
        }
        guard
            let playlistClient,
            ownsPlaylistLoad(context, client: playlistClient)
        else {
            playlists = []
            selectedPlaylistID = nil
            playlistListState = .ready
            await loadSelectedPlaylistTracks()
            return
        }

        playlistListState = .loading
        do {
            let loadedPlaylists = try await playlistClient.playlists()
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
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
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
            let failure = LibraryStoreFailure(message: error.localizedDescription)
            playlistListState = .failed(failure)
            recordOperationFailure(.playlistList, error: error)
        }
    }

    @discardableResult
    func createPlaylist(
        name: String = "Untitled Playlist"
    ) async -> LibraryPlaylistProjection? {
        let context = captureLibraryContext()
        guard
            let playlistClient,
            ownsPlaylistLoad(context, client: playlistClient)
        else {
            return nil
        }
        do {
            let playlist = try await playlistClient.create(name)
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return nil
            }
            selectedPlaylistID = playlist.id
            await loadPlaylists()
            return playlist
        } catch {
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return nil
            }
            recordOperationFailure(.playlistCreate, error: error)
            return nil
        }
    }

    @discardableResult
    func renameSelectedPlaylist(to name: String) async -> Bool {
        let description = playlists.first { $0.id == selectedPlaylistID }?
            .userDescription
        return await updateSelectedPlaylist(
            name: name,
            userDescription: description
        )
    }

    @discardableResult
    func updateSelectedPlaylist(
        name: String,
        userDescription: String?
    ) async -> Bool {
        let context = captureLibraryContext()
        guard
            let playlistClient,
            let selectedPlaylistID,
            ownsPlaylistLoad(context, client: playlistClient)
        else {
            return false
        }
        do {
            try await playlistClient.updateMetadata(
                selectedPlaylistID,
                name,
                userDescription
            )
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return false
            }
            await loadPlaylists()
            return true
        } catch {
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return false
            }
            recordOperationFailure(.playlistRename, error: error)
            return false
        }
    }

    func deleteSelectedPlaylist() async {
        let context = captureLibraryContext()
        guard
            let playlistClient,
            let selectedPlaylistID,
            ownsPlaylistLoad(context, client: playlistClient)
        else {
            return
        }
        do {
            try await playlistClient.delete(selectedPlaylistID)
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
            self.selectedPlaylistID = nil
            await loadPlaylists()
        } catch {
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
            recordOperationFailure(.playlistDelete, error: error)
        }
    }

    func selectPlaylist(_ id: UUID) async {
        guard attachmentPhase == .active else {
            return
        }
        selectedPlaylistID = id
        await loadSelectedPlaylistTracks()
    }

    func addToPlaylist(playlistID: UUID, trackIDs: [UUID]) async {
        let context = captureLibraryContext()
        guard
            let playlistClient,
            ownsPlaylistLoad(context, client: playlistClient)
        else {
            return
        }
        do {
            try await playlistClient.add(playlistID, trackIDs)
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
            await loadPlaylists()
        } catch {
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
            recordOperationFailure(.playlistAdd, error: error)
        }
    }

    func addToPlaylistConfirmingPersistence(
        playlistID: UUID,
        trackIDs: [UUID]
    ) async throws {
        let context = captureLibraryContext()
        guard
            let playlistClient,
            ownsPlaylistLoad(context, client: playlistClient)
        else {
            throw CancellationError()
        }
        do {
            try await playlistClient.add(playlistID, trackIDs)
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                throw CancellationError()
            }
            await loadPlaylists()
        } catch {
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                throw CancellationError()
            }
            recordOperationFailure(.playlistAdd, error: error)
            throw error
        }
    }

    func removeFromSelectedPlaylist(
        playlistID: UUID,
        trackIDs: [UUID]
    ) async {
        let context = captureLibraryContext()
        guard
            let playlistClient,
            ownsPlaylistLoad(context, client: playlistClient),
            ownsSelectedPlaylistTracks(for: playlistID)
        else {
            return
        }
        do {
            try await playlistClient.remove(playlistID, trackIDs)
            guard
                ownsPlaylistLoad(context, client: playlistClient),
                ownsSelectedPlaylistTracks(for: playlistID)
            else {
                return
            }
            await loadPlaylists()
        } catch {
            guard
                ownsPlaylistLoad(context, client: playlistClient),
                ownsSelectedPlaylistTracks(for: playlistID)
            else {
                return
            }
            recordOperationFailure(.playlistRemove, error: error)
        }
    }

    func reorderSelectedPlaylist(
        playlistID: UUID,
        trackIDs: [UUID]
    ) async {
        let context = captureLibraryContext()
        guard
            let playlistClient,
            ownsPlaylistLoad(context, client: playlistClient),
            ownsSelectedPlaylistTracks(for: playlistID)
        else {
            return
        }
        do {
            try await playlistClient.reorder(playlistID, trackIDs)
            guard
                ownsPlaylistLoad(context, client: playlistClient),
                ownsSelectedPlaylistTracks(for: playlistID)
            else {
                return
            }
            await loadSelectedPlaylistTracks()
        } catch {
            guard
                ownsPlaylistLoad(context, client: playlistClient),
                ownsSelectedPlaylistTracks(for: playlistID)
            else {
                return
            }
            recordOperationFailure(.playlistReorder, error: error)
        }
    }

    func loadSelectedPlaylistTracks() async {
        let context = captureLibraryContext()
        guard attachmentPhase == .active else {
            return
        }
        selectedPlaylistTracksGeneration &+= 1
        let generation = selectedPlaylistTracksGeneration
        guard let playlistClient, let selectedPlaylistID else {
            retireSelectedPlaylistTracksContent()
            selectedPlaylistTracksState = .ready
            return
        }

        selectedPlaylistTracksState = .loading
        do {
            let loadedTracks = try await playlistClient.playlistTracks(
                selectedPlaylistID
            )
            guard
                ownsPlaylistLoad(context, client: playlistClient),
                self.selectedPlaylistID == selectedPlaylistID,
                selectedPlaylistTracksGeneration == generation
            else {
                return
            }
            replaceSelectedPlaylistTracksContent(
                with: loadedTracks,
                ownerID: selectedPlaylistID
            )
            selectedPlaylistTracksState = .ready
        } catch {
            guard
                ownsPlaylistLoad(context, client: playlistClient),
                self.selectedPlaylistID == selectedPlaylistID,
                selectedPlaylistTracksGeneration == generation
            else {
                return
            }
            let failure = LibraryStoreFailure(message: error.localizedDescription)
            selectedPlaylistTracksState = .failed(failure)
            recordOperationFailure(.playlistTracks, error: error)
        }
    }

    private func ownsPlaylistLoad(
        _ context: LibraryStoreContext,
        client: LibraryPlaylistClient
    ) -> Bool {
        isCurrentLibraryContext(context)
            && playlistClient?.attachmentID == client.attachmentID
    }

    func addAlbum(_ albumID: UUID, to playlistID: UUID) async {
        let context = captureLibraryContext()
        guard
            let playlistClient,
            ownsPlaylistLoad(context, client: playlistClient)
        else {
            return
        }
        do {
            let trackIDs = try await playlistClient.albumTrackIDs(albumID)
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
            try await playlistClient.add(playlistID, trackIDs)
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
            await loadPlaylists()
        } catch {
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
            recordOperationFailure(.playlistAdd, error: error)
        }
    }

    func addArtist(_ artistID: UUID, to playlistID: UUID) async {
        let context = captureLibraryContext()
        guard
            let playlistClient,
            ownsPlaylistLoad(context, client: playlistClient)
        else {
            return
        }
        do {
            let trackIDs = try await playlistClient.artistTrackIDs(artistID)
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
            try await playlistClient.add(playlistID, trackIDs)
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
            await loadPlaylists()
        } catch {
            guard ownsPlaylistLoad(context, client: playlistClient) else {
                return
            }
            recordOperationFailure(.playlistAdd, error: error)
        }
    }
}
