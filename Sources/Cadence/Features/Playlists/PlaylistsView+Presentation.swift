import SwiftUI

enum PlaylistPlaybackPresentation {
    static func isEnabled(
        ownsLoadedTracks: Bool,
        trackCount: Int
    ) -> Bool {
        ownsLoadedTracks && trackCount > 0
    }
}

extension PlaylistsView {
    var playlistNameValidation: PlaylistNameValidation {
        PlaylistNamePolicy.validation(
            playlistName,
            existingPlaylists: store.playlists.map { ($0.id, $0.name) },
            excludingID: playlistNameOperation == .rename
                ? store.selectedPlaylistID
                : nil
        )
    }

    var playlistNameValidationMessage: String {
        let count = PlaylistNamePolicy.normalizedName(playlistName).count
        let counter = String(
            localized: "\(count) of \(PlaylistNamePolicy.maximumLength) characters"
        )
        guard let errorMessage = playlistNameValidation.errorMessage else {
            return counter
        }
        return "\(errorMessage)\n\(counter)"
    }

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
        .disabled(
            !PlaylistPlaybackPresentation.isEnabled(
                ownsLoadedTracks: store.ownsSelectedPlaylistTracks(
                    for: playlist.id
                ),
                trackCount: playlist.trackCount
            )
        )
    }

    func playPlaylist(
        _ playlist: LibraryPlaylistProjection,
        shuffled: Bool
    ) {
        guard let source = store.selectedPlaylistTrackSource(
            for: playlist.id
        ) else {
            return
        }
        let tracks = source.tracks
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

enum PlaylistNameOperation: Equatable {
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

    var initialName: String {
        ""
    }
}
