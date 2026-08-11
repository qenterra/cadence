import SwiftUI

struct ProductionAlbumDetailView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let albumID: UUID

    @State private var album: LibraryAlbumProjection?
    @State private var tracks: [LibraryTrackProjection] = []
    @State private var albumTags: [LibraryTagProjection] = []
    @State private var isLoading = true
    @State private var isRenamePresented = false
    @State private var renameDraft = ""

    var body: some View {
        Group {
            if let album {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        backButton
                        header(album)
                        ProductionTrackList(
                            model: model,
                            tracks: tracks,
                            context: .album(albumID)
                        )
                        .frame(
                            height: min(
                                max(CGFloat(tracks.count * 58 + 38), 240),
                                520
                            )
                        )
                    }
                    .padding(28)
                }
            } else if isLoading {
                ProgressView("Loading Album")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Album Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This album is no longer in the library.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(CadenceTheme.contentBackground)
        .catalogRenameAlert(
            "Rename Album",
            prompt: "Album Name",
            isPresented: $isRenamePresented,
            draft: $renameDraft
        ) { title in
            Task {
                if let renamed = await model.renameProductionAlbum(
                    id: albumID,
                    title: title
                ) {
                    album = renamed
                }
            }
        }
        .task(id: "\(albumID.uuidString)-\(store.tagRevision)") {
            isLoading = true
            async let loadedAlbum = store.album(id: albumID)
            async let loadedTracks = store.tracks(albumID: albumID)
            async let loadedTags = try? store.tags(albumID: albumID)
            album = await loadedAlbum
            tracks = await loadedTracks
            albumTags = await loadedTags ?? []
            isLoading = false
        }
    }

    private var backButton: some View {
        Button {
            model.requestContextualBack()
        } label: {
            Label("Back to \(model.contextualBackTitle)", systemImage: "chevron.left")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func header(
        _ album: LibraryAlbumProjection
    ) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            ProductionArtworkView(
                model: model,
                artworkID: album.customArtworkID,
                title: album.title,
                placeholder: .album,
                variant: .original,
                cornerRadius: CadenceTheme.radiusPanel
            )
            .frame(width: 210, height: 210)
            .contextMenu {
                ArtworkMenuItems(
                    model: model,
                    target: .managedAlbum(album.id),
                    label: "Album Artwork"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ALBUM")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                albumTitle(album)
                Button {
                    guard let artistID = album.artistID else {
                        return
                    }
                    model.requestOpenProductionArtistContextually(id: artistID)
                } label: {
                    Text(album.artist)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(album.artistID == nil)
                Text(albumMetadata(album))
                    .font(.callout)
                    .foregroundStyle(.tertiary)

                playbackActions(album)
                albumTagChips
            }
            Spacer()
            Menu {
                albumActions(album)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .help("Album Actions")
        }
    }

    private func playbackActions(
        _ album: LibraryAlbumProjection
    ) -> some View {
        HStack(spacing: 10) {
            Button("Play", systemImage: "play.fill") {
                model.playProductionAlbum(album, tracks: tracks)
            }
            .buttonStyle(.borderedProminent)
            .disabled(tracks.isEmpty)

            Button("Shuffle", systemImage: "shuffle") {
                model.playProductionAlbum(
                    album,
                    tracks: tracks,
                    shuffled: true
                )
            }
            .buttonStyle(.bordered)
            .disabled(tracks.isEmpty)

            Button(
                album.isFavorite ? "Unfavorite" : "Favorite",
                systemImage: album.isFavorite ? "heart.fill" : "heart"
            ) {
                Task {
                    if let updated = await model.setProductionAlbumFavorite(
                        album,
                        isFavorite: !album.isFavorite
                    ) {
                        self.album = updated
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var albumTagChips: some View {
        if !albumTags.isEmpty {
            CadenceFlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                ForEach(albumTags) { tag in
                    Button {
                        model.requestOpenProductionTagContextually(
                            id: tag.id
                        )
                    } label: {
                        Label(tag.displayPath, systemImage: "tag")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(
                                CadenceTheme.subduedFill,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func albumActions(
        _ album: LibraryAlbumProjection
    ) -> some View {
        Button("Rename", systemImage: "pencil") {
            beginRename(album)
        }
        QuickAlbumTagMenuItems(
            store: store,
            albumID: album.id
        )
        AddAlbumToPlaylistMenuItems(
            store: store,
            albumID: album.id
        )
        ArtworkMenuItems(
            model: model,
            target: .managedAlbum(album.id),
            label: "Album Artwork"
        )
        Divider()
        Button(
            "Move Album to Trash…",
            systemImage: "trash",
            role: .destructive
        ) {
            model.requestLibraryDeletion(
                kind: .album,
                id: album.id,
                title: album.title
            )
        }
    }

    private func beginRename(_ album: LibraryAlbumProjection) {
        renameDraft = album.title
        isRenamePresented = true
    }
}

private extension ProductionAlbumDetailView {
    func albumTitle(_ album: LibraryAlbumProjection) -> some View {
        Text(album.title)
            .font(.largeTitle.bold())
            .onTapGesture(count: 2) {
                beginRename(album)
            }
    }

    func albumMetadata(_ album: LibraryAlbumProjection) -> String {
        var parts = ["\(album.trackCount) tracks"]
        if let year = album.year {
            parts.append(year.formatted(.number.grouping(.never)))
        }
        return parts.joined(separator: " · ")
    }
}
