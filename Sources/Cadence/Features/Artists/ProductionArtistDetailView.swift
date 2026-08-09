import SwiftUI

struct ProductionArtistDetailView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let artistID: UUID

    @State private var artist: LibraryArtistProjection?
    @State private var albums: [LibraryAlbumProjection] = []
    @State private var tracks: [LibraryTrackProjection] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if let artist {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        backButton
                        header(artist)
                        CadenceSeparator()
                        if !albums.isEmpty {
                            Text("Albums")
                                .font(.title2.bold())
                            albumGrid
                            CadenceSeparator()
                        }
                        Text("Tracks")
                            .font(.title2.bold())
                        ProductionTrackList(
                            model: model,
                            tracks: tracks,
                            context: .artist(artistID)
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
                ProgressView("Loading Artist")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                unavailableContent("Artist")
            }
        }
        .task(id: artistID) {
            isLoading = true
            async let loadedArtist = store.artist(id: artistID)
            async let loadedAlbums = store.albums(artistID: artistID)
            async let loadedTracks = store.tracks(artistID: artistID)
            artist = await loadedArtist
            albums = await loadedAlbums
            tracks = await loadedTracks
            isLoading = false
        }
    }

    private var albumGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 170), spacing: 16),
            ],
            alignment: .leading,
            spacing: 18
        ) {
            ForEach(albums) { album in
                albumTile(album)
            }
        }
    }

    private func albumTile(
        _ album: LibraryAlbumProjection
    ) -> some View {
        Button {
            model.requestOpenProductionAlbumContextually(id: album.id)
        } label: {
            albumTileLabel(album)
        }
        .buttonStyle(.plain)
        .contextMenu {
            albumActions(album)
        }
    }

    private func albumTileLabel(
        _ album: LibraryAlbumProjection
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProductionArtworkView(
                model: model,
                artworkID: album.customArtworkID,
                title: album.title,
                placeholder: .album,
                cornerRadius: CadenceTheme.radiusGroup
            )
            .aspectRatio(1, contentMode: .fit)

            Text(album.title)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(
                album.year?.formatted(.number.grouping(.never))
                    ?? "\(album.trackCount) tracks"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
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
        _ artist: LibraryArtistProjection
    ) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            ProductionArtworkView(
                model: model,
                artworkID: artist.customArtworkID,
                title: artist.name,
                placeholder: .artist,
                variant: .original,
                cornerRadius: CadenceTheme.radiusNone,
                showsBorder: false
            )
            .frame(width: 190, height: 190)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text("ARTIST")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(artist.name)
                    .font(.largeTitle.bold())
                Text(
                    "\(artist.albumCount) albums · \(artist.trackCount) tracks"
                )
                .foregroundStyle(.secondary)
                playbackActions(artist)
            }
            Spacer()
            Menu {
                artistActions(artist)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .help("Artist Actions")
        }
    }

    private func playbackActions(
        _ artist: LibraryArtistProjection
    ) -> some View {
        HStack(spacing: 10) {
            Button("Play", systemImage: "play.fill") {
                model.playProductionArtist(artist, tracks: tracks)
            }
            .buttonStyle(.borderedProminent)
            .disabled(tracks.isEmpty)

            Button("Shuffle", systemImage: "shuffle") {
                model.playProductionArtist(
                    artist,
                    tracks: tracks,
                    shuffled: true
                )
            }
            .buttonStyle(.bordered)
            .disabled(tracks.isEmpty)

            Button(
                artist.isFavorite ? "Unfavorite" : "Favorite",
                systemImage: artist.isFavorite ? "heart.fill" : "heart"
            ) {
                Task {
                    if let updated = await model.setProductionArtistFavorite(
                        artist,
                        isFavorite: !artist.isFavorite
                    ) {
                        self.artist = updated
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func artistActions(
        _ artist: LibraryArtistProjection
    ) -> some View {
        AddArtistToPlaylistMenuItems(
            store: store,
            artistID: artist.id
        )
        ArtworkMenuItems(
            model: model,
            target: .managedArtist(artist.id),
            label: "Artist Image"
        )
        Divider()
        Button(
            "Move Artist to Trash…",
            systemImage: "trash",
            role: .destructive
        ) {
            model.requestLibraryDeletion(
                kind: .artist,
                id: artist.id,
                title: artist.name
            )
        }
    }

    private func unavailableContent(
        _ kind: String
    ) -> some View {
        ContentUnavailableView(
            "\(kind) Unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("This item is no longer in the library.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func albumActions(
        _ album: LibraryAlbumProjection
    ) -> some View {
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
}
