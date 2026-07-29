import SwiftUI

struct PlaylistsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore

    @State private var isCreatingPlaylist = false
    @State private var isRenamingPlaylist = false
    @State private var isDeletingPlaylist = false
    @State private var playlistName = ""
    @AppStorage("playlists.sidebarWidth")
    private var sidebarWidth = 270.0

    var body: some View {
        CadenceResizableSplitView(
            fixedPane: .leading,
            fixedWidth: $sidebarWidth,
            fixedMinimum: 230,
            fixedMaximum: 400,
            flexibleMinimum: 520
        ) {
            sidebar
        } trailing: {
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.contentBackground)
        .task {
            await store.loadPlaylists()
        }
        .alert("New Playlist", isPresented: $isCreatingPlaylist) {
            TextField("Playlist Name", text: $playlistName)
            Button("Create") {
                let name = playlistName
                playlistName = ""
                Task {
                    await store.createPlaylist(name: name)
                }
            }
            Button("Cancel", role: .cancel) {
                playlistName = ""
            }
        }
        .alert("Rename Playlist", isPresented: $isRenamingPlaylist) {
            TextField("Playlist Name", text: $playlistName)
            Button("Rename") {
                let name = playlistName
                playlistName = ""
                Task {
                    await store.renameSelectedPlaylist(to: name)
                }
            }
            Button("Cancel", role: .cancel) {
                playlistName = ""
            }
        }
        .confirmationDialog(
            "Delete Playlist?",
            isPresented: $isDeletingPlaylist
        ) {
            Button("Delete Playlist", role: .destructive) {
                Task {
                    await store.deleteSelectedPlaylist()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tracks remain in your Cadence library.")
        }
    }
}

private extension PlaylistsView {
    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Playlists")
                    .font(.title2.bold())
                Spacer()
                Button {
                    playlistName = ""
                    isCreatingPlaylist = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Playlist")
            }
            .padding(.horizontal, 18)
            .frame(height: 68)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            if store.playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text(
                        "Create a playlist, then add music from any track menu."
                    )
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.playlists) { playlist in
                            playlistRow(playlist)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let playlist = selectedPlaylist {
            VStack(spacing: 0) {
                playlistHeader(playlist)

                if store.selectedPlaylistTracks.isEmpty {
                    ContentUnavailableView(
                        "Empty Playlist",
                        systemImage: "music.note.list",
                        description: Text(
                            "Add tracks, albums, or artists from their ••• menu."
                        )
                    )
                } else {
                    ScrollView {
                        ProductionTrackTable(
                            model: model,
                            tracks: store.selectedPlaylistTracks,
                            playlistID: playlist.id,
                            queueSource: .playlist(playlist.id),
                            reorderAction: { trackIDs in
                                Task {
                                    await store.reorderSelectedPlaylist(
                                        trackIDs: trackIDs
                                    )
                                }
                            }
                        )
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Choose a Playlist",
                systemImage: "music.note.list"
            )
        }
    }

    private func playlistRow(
        _ playlist: LibraryPlaylistProjection
    ) -> some View {
        Button {
            Task {
                await store.selectPlaylist(playlist.id)
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "music.note.list")
                    .frame(width: 28, height: 28)
                    .background(
                        CadenceTheme.subduedFill,
                        in: RoundedRectangle(cornerRadius: 6)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(playlist.trackCount) tracks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    playlistActions(playlist)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 26, height: 26)
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 10)
            .frame(height: 54)
            .background {
                BrowserRowSurface(
                    isSelected: store.selectedPlaylistID == playlist.id,
                    isHovered: false,
                    isFocused: false
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            playlistActions(playlist)
        }
    }

    private func playlistHeader(
        _ playlist: LibraryPlaylistProjection
    ) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            playlistArtwork
            playlistHeaderDetails(playlist)

            Spacer()

            Menu {
                playlistActions(playlist)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
        }
        .padding(28)
    }

    private var playlistArtwork: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(CadenceTheme.secondarySurface)
            .overlay {
                Image(systemName: "music.note.list")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, height: 150)
    }

    private func playlistHeaderDetails(
        _ playlist: LibraryPlaylistProjection
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PLAYLIST")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(playlist.name)
                .font(.largeTitle.bold())
            Text(
                "\(playlist.trackCount) tracks · "
                    + timeText(playlist.totalDuration)
            )
            .foregroundStyle(.secondary)
            playlistPlaybackButtons(playlist)
        }
    }

    private func playlistPlaybackButtons(
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

    private func playPlaylist(
        _ playlist: LibraryPlaylistProjection,
        shuffled: Bool
    ) {
        let tracks = store.selectedPlaylistTracks
        guard
            let first = shuffled ? tracks.randomElement() : tracks.first
        else {
            return
        }
        model.playProductionTrack(
            first,
            within: tracks,
            source: .playlist(playlist.id),
            isShuffled: shuffled
        )
    }

    @ViewBuilder
    private func playlistActions(
        _ playlist: LibraryPlaylistProjection
    ) -> some View {
        Button("Rename…", systemImage: "pencil") {
            Task {
                await store.selectPlaylist(playlist.id)
                playlistName = playlist.name
                isRenamingPlaylist = true
            }
        }
        Button(
            "Delete Playlist…",
            systemImage: "trash",
            role: .destructive
        ) {
            Task {
                await store.selectPlaylist(playlist.id)
                isDeletingPlaylist = true
            }
        }
    }

    private var selectedPlaylist: LibraryPlaylistProjection? {
        guard let id = store.selectedPlaylistID else {
            return nil
        }
        return store.playlists.first { $0.id == id }
    }

    private func timeText(
        _ duration: TimeInterval
    ) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
