import Foundation

extension LibraryStore {
    func loadPlaylists() async {
        guard let repository else {
            playlists = []
            return
        }
        playlists = await (try? repository.playlists()) ?? []
        if let selectedPlaylistID,
           !playlists.contains(where: { $0.id == selectedPlaylistID }) {
            self.selectedPlaylistID = playlists.first?.id
        } else if selectedPlaylistID == nil {
            selectedPlaylistID = playlists.first?.id
        }
        await loadSelectedPlaylistTracks()
    }

    func createPlaylist(
        name: String = "Untitled Playlist"
    ) async {
        guard let repository else {
            return
        }
        if let playlist = try? await repository.createPlaylist(name: name) {
            selectedPlaylistID = playlist.id
        }
        await loadPlaylists()
    }

    func renameSelectedPlaylist(
        to name: String
    ) async {
        guard let repository, let selectedPlaylistID else {
            return
        }
        try? await repository.renamePlaylist(
            id: selectedPlaylistID,
            name: name
        )
        await loadPlaylists()
    }

    func deleteSelectedPlaylist() async {
        guard let repository, let selectedPlaylistID else {
            return
        }
        try? await repository.deletePlaylist(id: selectedPlaylistID)
        self.selectedPlaylistID = nil
        await loadPlaylists()
    }

    func selectPlaylist(
        _ id: UUID
    ) async {
        selectedPlaylistID = id
        await loadSelectedPlaylistTracks()
    }

    func addToPlaylist(
        playlistID: UUID,
        trackIDs: [UUID]
    ) async {
        guard let repository else {
            return
        }
        try? await repository.addToPlaylist(
            playlistID: playlistID,
            trackIDs: trackIDs
        )
        await loadPlaylists()
    }

    func removeFromSelectedPlaylist(
        trackIDs: [UUID]
    ) async {
        guard let repository, let selectedPlaylistID else {
            return
        }
        try? await repository.removeFromPlaylist(
            playlistID: selectedPlaylistID,
            trackIDs: trackIDs
        )
        await loadPlaylists()
    }

    func reorderSelectedPlaylist(
        trackIDs: [UUID]
    ) async {
        guard let repository, let selectedPlaylistID else {
            return
        }
        try? await repository.reorderPlaylist(
            playlistID: selectedPlaylistID,
            orderedTrackIDs: trackIDs
        )
        await loadSelectedPlaylistTracks()
    }

    func loadSelectedPlaylistTracks() async {
        guard let repository, let selectedPlaylistID else {
            selectedPlaylistTracks = []
            return
        }
        selectedPlaylistTracks = await (
            try? repository.playlistTracks(
                playlistID: selectedPlaylistID
            )
        ) ?? []
    }

    func addAlbum(
        _ albumID: UUID,
        to playlistID: UUID
    ) async {
        guard let repository else {
            return
        }
        let trackIDs = await (
            try? repository.playlistTrackIDs(albumID: albumID)
        ) ?? []
        await addToPlaylist(
            playlistID: playlistID,
            trackIDs: trackIDs
        )
    }

    func addArtist(
        _ artistID: UUID,
        to playlistID: UUID
    ) async {
        guard let repository else {
            return
        }
        let trackIDs = await (
            try? repository.playlistTrackIDs(artistID: artistID)
        ) ?? []
        await addToPlaylist(
            playlistID: playlistID,
            trackIDs: trackIDs
        )
    }
}
