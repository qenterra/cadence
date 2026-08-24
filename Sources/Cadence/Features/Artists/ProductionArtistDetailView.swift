import SwiftUI

struct ProductionArtistDetailView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let artistID: UUID
    @State private var artist: LibraryArtistProjection?
    @State private var releases = ArtistReleaseSections.empty
    @State private var tracks: [LibraryTrackProjection] = []
    @State private var tracksClock = TrackTableContentClock()
    @State private var isLoading = true
    @State private var loadFailure: String?
    @State private var loadGeneration = 0
    @State private var isRenamePresented = false
    @State private var renameDraft = ""

    var body: some View {
        Group {
            if let artist {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        backButton
                        refreshFailureNotice
                        header(artist)
                        favoriteTracksSection
                        releaseSection("Singles", releases.singles)
                        releaseSection("EPs", releases.eps)
                        releaseSection("Albums", releases.albums)
                        releaseSection("Appears On", releases.appearsOn)
                        Text("All Tracks")
                            .font(.title2.bold())
                        ProductionTrackList(
                            model: model,
                            tracks: tracks,
                            contentVersion: tracksClock.version,
                            context: .artist(artistID),
                            defaultSortDescriptor: TrackTableSortDescriptor(
                                field: .year,
                                direction: .descending
                            )
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
            } else if let loadFailure {
                ContentUnavailableView {
                    Label(
                        "Couldn’t Load Artist",
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(loadFailure)
                } actions: {
                    Button("Retry") {
                        loadGeneration &+= 1
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                unavailableContent("Artist")
            }
        }
        .task(id: "\(artistID.uuidString)-\(loadGeneration)") {
            isLoading = true
            do {
                async let loadedArtist = store.artist(id: artistID)
                async let loadedReleases = store.artistReleaseSections(
                    artistID: artistID
                )
                async let loadedTracks = store.tracks(artistID: artistID)
                let result = try await (
                    artist: loadedArtist,
                    releases: loadedReleases,
                    tracks: loadedTracks
                )
                artist = result.artist
                releases = result.releases
                if tracks != result.tracks {
                    tracks = result.tracks
                    tracksClock.advance()
                }
                applyArtworkPublication()
                loadFailure = nil
            } catch {
                loadFailure = error.localizedDescription
            }
            isLoading = false
        }
        .catalogRenameAlert(
            "Rename Artist",
            prompt: "Artist Name",
            isPresented: $isRenamePresented,
            draft: $renameDraft
        ) { name in
            Task {
                if let renamed = await model.renameProductionArtist(
                    id: artistID,
                    name: name
                ) {
                    artist = renamed
                }
            }
        }
        .onChange(of: store.artworkPublication?.generation) {
            applyArtworkPublication()
        }
    }
}

private extension ProductionArtistDetailView {
    func applyArtworkPublication() {
        guard
            let publication = store.artworkPublication,
            publication.epoch == store.libraryEpoch
        else {
            return
        }
        if let replacement = publication.artistsByID[artistID] {
            artist = replacement
        }
        releases = publication.mergingAlbums(in: releases)
        if publication.mergeTracks(into: &tracks) {
            tracksClock.advance()
        }
    }

    @ViewBuilder
    var refreshFailureNotice: some View {
        if let loadFailure {
            HStack {
                Label(loadFailure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry") {
                    loadGeneration &+= 1
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteTracksSection: some View {
        let favorites = tracks.filter(\.isFavorite)
        if !favorites.isEmpty {
            Text("Favorite Tracks")
                .font(.title2.bold())
            ProductionTrackList(
                model: model,
                tracks: favorites,
                contentVersion: tracksClock.version,
                context: .artist(artistID),
                defaultSortDescriptor: TrackTableSortDescriptor(
                    field: .year,
                    direction: .descending
                )
            )
            .frame(
                height: min(
                    max(CGFloat(favorites.count * 58 + 38), 154),
                    386
                )
            )
        }
    }

    private func albumGrid(
        _ albums: [LibraryAlbumProjection]
    ) -> some View {
        LazyVGrid(
            columns: CatalogCardLayoutMetrics.layoutColumns(spacing: 16),
            alignment: .leading,
            spacing: 18
        ) {
            ForEach(albums) { album in
                albumTile(album)
            }
        }
    }

    @ViewBuilder
    private func releaseSection(
        _ title: String,
        _ albums: [LibraryAlbumProjection]
    ) -> some View {
        if !albums.isEmpty {
            Text(title)
                .font(.title2.bold())
            albumGrid(albums)
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
        .frame(width: CatalogCardLayoutMetrics.cardWidth)
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
            .contextMenu {
                ArtworkMenuItems(
                    model: model,
                    target: .managedArtist(artist.id),
                    label: "Artist Image"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ARTIST")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(artist.name)
                    .font(.largeTitle.bold())
                    .onTapGesture(count: 2) {
                        beginRename(artist)
                    }
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
        Button("Rename", systemImage: "pencil") {
            beginRename(artist)
        }
        Button(
            HomePinStore.contains(artist.id, in: .artist)
                ? "Unpin from Home"
                : "Pin to Home",
            systemImage: HomePinStore.contains(artist.id, in: .artist)
                ? "pin.slash"
                : "pin"
        ) {
            HomePinStore.toggle(artist.id, in: .artist)
        }
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

    private func beginRename(_ artist: LibraryArtistProjection) {
        renameDraft = artist.name
        isRenamePresented = true
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
