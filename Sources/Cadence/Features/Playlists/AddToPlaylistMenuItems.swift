import SwiftUI

struct AddToPlaylistMenuItems: View {
    @Bindable var store: LibraryStore
    let trackIDs: [UUID]

    var body: some View {
        Menu("Add to Playlist", systemImage: "text.badge.plus") {
            if store.playlists.isEmpty {
                Button("New Playlist…", systemImage: "plus") {
                    Task {
                        await store.createPlaylist()
                        guard let playlistID = store.selectedPlaylistID else {
                            return
                        }
                        await store.addToPlaylist(
                            playlistID: playlistID,
                            trackIDs: trackIDs
                        )
                    }
                }
            } else {
                ForEach(store.playlists) { playlist in
                    Button(playlist.name) {
                        Task {
                            await store.addToPlaylist(
                                playlistID: playlist.id,
                                trackIDs: trackIDs
                            )
                        }
                    }
                }

                Divider()

                Button("New Playlist…", systemImage: "plus") {
                    Task {
                        await store.createPlaylist()
                        guard let playlistID = store.selectedPlaylistID else {
                            return
                        }
                        await store.addToPlaylist(
                            playlistID: playlistID,
                            trackIDs: trackIDs
                        )
                    }
                }
            }
        }
        .disabled(trackIDs.isEmpty)
    }
}

struct AddAlbumToPlaylistMenuItems: View {
    @Bindable var store: LibraryStore
    let albumID: UUID

    var body: some View {
        Menu("Add Album to Playlist", systemImage: "text.badge.plus") {
            ForEach(store.playlists) { playlist in
                Button(playlist.name) {
                    Task {
                        await store.addAlbum(albumID, to: playlist.id)
                    }
                }
            }

            if !store.playlists.isEmpty {
                Divider()
            }

            Button("New Playlist…", systemImage: "plus") {
                Task {
                    await store.createPlaylist()
                    guard let playlistID = store.selectedPlaylistID else {
                        return
                    }
                    await store.addAlbum(albumID, to: playlistID)
                }
            }
        }
    }
}

struct AddArtistToPlaylistMenuItems: View {
    @Bindable var store: LibraryStore
    let artistID: UUID

    var body: some View {
        Menu("Add Artist to Playlist", systemImage: "text.badge.plus") {
            ForEach(store.playlists) { playlist in
                Button(playlist.name) {
                    Task {
                        await store.addArtist(artistID, to: playlist.id)
                    }
                }
            }

            if !store.playlists.isEmpty {
                Divider()
            }

            Button("New Playlist…", systemImage: "plus") {
                Task {
                    await store.createPlaylist()
                    guard let playlistID = store.selectedPlaylistID else {
                        return
                    }
                    await store.addArtist(artistID, to: playlistID)
                }
            }
        }
    }
}
