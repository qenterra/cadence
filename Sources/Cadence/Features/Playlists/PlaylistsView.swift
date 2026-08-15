import SwiftUI

struct PlaylistsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore

    @State var playlistNameOperation: PlaylistNameOperation?
    @State private var isDeletingPlaylist = false
    @State private var playlistName = ""
    @AppStorage("playlists.sidebarWidth")
    private var sidebarWidth = 270.0

    var body: some View {
        CadenceResizableSplitView(
            fixedPane: .leading,
            fixedWidth: $sidebarWidth,
            fixedMinimum: WorkspaceLayout.paneMinimumWidth,
            fixedMaximum: WorkspaceLayout.paneMaximumWidth,
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
        .alert(
            playlistNameOperation?.title ?? "Playlist",
            isPresented: playlistNameOperationPresented
        ) {
            TextField("Playlist Name", text: $playlistName)
            Button(playlistNameOperation?.actionTitle ?? "Save") {
                let operation = playlistNameOperation
                let name = playlistName
                playlistNameOperation = nil
                playlistName = ""
                Task {
                    switch operation {
                    case .create:
                        await store.createPlaylist(name: name)
                    case .rename:
                        await store.renameSelectedPlaylist(to: name)
                    case nil:
                        break
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                playlistNameOperation = nil
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
            WorkspacePaneHeader("Playlists") {
                Button {
                    playlistName = "Untitled Playlist"
                    playlistNameOperation = .create
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Playlist")
            }

            if store.playlistListState == .loading, store.playlists.isEmpty {
                ProgressView("Loading Playlists")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure = store.playlistListState.failure,
                      store.playlists.isEmpty {
                ContentUnavailableView {
                    Label(
                        "Couldn’t Load Playlists",
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(failure.message)
                } actions: {
                    Button("Retry") {
                        Task {
                            await store.loadPlaylists()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text(
                        "Create a playlist, then add music from any track menu."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(store.playlists) { playlist in
                            playlistRow(playlist)
                        }
                    }
                    .padding(.horizontal, WorkspaceLayout.listInset)
                    .padding(.top, WorkspaceLayout.listInset)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let playlist = selectedPlaylist {
            VStack(spacing: 0) {
                playlistHeader(playlist)

                if store.selectedPlaylistTracksState == .loading,
                   store.selectedPlaylistTracks.isEmpty {
                    ProgressView("Loading Playlist")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let failure = store.selectedPlaylistTracksState.failure,
                          store.selectedPlaylistTracks.isEmpty {
                    ContentUnavailableView {
                        Label(
                            "Couldn’t Load Playlist",
                            systemImage: "exclamationmark.triangle"
                        )
                    } description: {
                        Text(failure.message)
                    } actions: {
                        Button("Retry") {
                            Task {
                                await store.loadSelectedPlaylistTracks()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.selectedPlaylistTracks.isEmpty {
                    ContentUnavailableView(
                        "Empty Playlist",
                        systemImage: "music.note.list",
                        description: Text(
                            "Add tracks, albums, or artists from their ••• menu."
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProductionTrackTable(
                        model: model,
                        tracks: store.selectedPlaylistTracks,
                        context: .playlist(playlist.id),
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
                    .padding(.bottom, 24)
                }
            }
        } else {
            ContentUnavailableView(
                "Choose a Playlist",
                systemImage: "music.note.list",
                description: Text("Choose a playlist to view its tracks.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func playlistRow(
        _ playlist: LibraryPlaylistProjection
    ) -> some View {
        HStack(spacing: 11) {
            playlistSelectionButton(playlist)
            playlistActionMenu(playlist)
        }
        .padding(.horizontal, 10)
        .frame(height: WorkspaceLayout.rowHeight)
        .background {
            BrowserRowSurface(
                isSelected: store.selectedPlaylistID == playlist.id,
                isHovered: false,
                isFocused: false
            )
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard store.selectedPlaylistID == playlist.id,
                  let first = store.selectedPlaylistTracks.first else {
                return
            }
            model.playProductionTrack(
                first,
                within: store.selectedPlaylistTracks,
                source: .playlist(playlist.id)
            )
        }
        .contextMenu {
            playlistActions(playlist)
        }
    }

    private func playlistSelectionButton(
        _ playlist: LibraryPlaylistProjection
    ) -> some View {
        Button {
            Task {
                await store.selectPlaylist(playlist.id)
            }
        } label: {
            HStack(spacing: 11) {
                ProductionArtworkView(
                    model: model,
                    artworkID: playlist.customArtworkID,
                    title: playlist.name,
                    placeholder: .playlist,
                    cornerRadius: CadenceTheme.radiusControl
                )
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(playlist.trackCount) tracks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func playlistActionMenu(
        _ playlist: LibraryPlaylistProjection
    ) -> some View {
        Menu {
            playlistActions(playlist)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 26, height: 26)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
    }

    private func playlistHeader(
        _ playlist: LibraryPlaylistProjection
    ) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            playlistArtwork(playlist)
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

    private func playlistArtwork(
        _ playlist: LibraryPlaylistProjection
    ) -> some View {
        ProductionArtworkView(
            model: model,
            artworkID: playlist.customArtworkID,
            title: playlist.name,
            placeholder: .playlist,
            variant: .original,
            cornerRadius: CadenceTheme.radiusPanel
        )
        .frame(width: 150, height: 150)
        .contextMenu {
            ArtworkMenuItems(
                model: model,
                target: .managedPlaylist(playlist.id),
                label: "Playlist Artwork"
            )
        }
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

    @ViewBuilder
    private func playlistActions(
        _ playlist: LibraryPlaylistProjection
    ) -> some View {
        Button(
            HomePinStore.contains(playlist.id, in: .playlist)
                ? "Unpin from Home"
                : "Pin to Home",
            systemImage: HomePinStore.contains(playlist.id, in: .playlist)
                ? "pin.slash"
                : "pin"
        ) {
            HomePinStore.toggle(playlist.id, in: .playlist)
        }
        ArtworkMenuItems(
            model: model,
            target: .managedPlaylist(playlist.id),
            label: "Playlist Artwork"
        )
        Divider()
        Button("Rename…", systemImage: "pencil") {
            Task {
                await store.selectPlaylist(playlist.id)
                playlistName = playlist.name
                playlistNameOperation = .rename
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
}
