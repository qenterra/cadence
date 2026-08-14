import SwiftUI

extension PlaylistsView {
    func playlistPlaybackButtons(
        _ playlist: LibraryPlaylistProjection
    ) -> some View {
        HStack {
            Button("Play", systemImage: "play.fill") {
                playPlaylist(playlist, shuffled: false)
            }
            .buttonStyle(.borderedProminent)

            Button("Shuffle", systemImage: "shuffle") {
                playPlaylist(playlist, shuffled: true)
            }
        }
    }

    func playPlaylist(
        _ playlist: LibraryPlaylistProjection,
        shuffled: Bool
    ) {
        let tracks = store.selectedPlaylistTracks
        guard let first = shuffled ? tracks.randomElement() : tracks.first else {
            return
        }
        model.playProductionTrack(
            first,
            within: tracks,
            source: .playlist(playlist.id),
            isShuffled: shuffled
        )
    }

    var selectedPlaylist: LibraryPlaylistProjection? {
        guard let id = store.selectedPlaylistID else {
            return nil
        }
        return store.playlists.first { $0.id == id }
    }

    var playlistNameOperationPresented: Binding<Bool> {
        Binding(
            get: { playlistNameOperation != nil },
            set: { isPresented in
                if !isPresented {
                    playlistNameOperation = nil
                }
            }
        )
    }

    func timeText(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

enum PlaylistNameOperation {
    case create
    case rename

    var title: String {
        switch self {
        case .create:
            String(localized: "New Playlist")
        case .rename:
            String(localized: "Rename Playlist")
        }
    }

    var actionTitle: String {
        switch self {
        case .create:
            String(localized: "Create")
        case .rename:
            String(localized: "Rename")
        }
    }
}
