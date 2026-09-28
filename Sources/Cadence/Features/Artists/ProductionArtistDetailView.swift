import SwiftUI

// The detail surface keeps its loading, header, release, and action states in one
// cohesive view so their contextual navigation state cannot drift apart.
// swiftlint:disable file_length

struct ProductionArtistDetailView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @Environment(\.catalogCardSize) private var catalogCardSize
    @Environment(\.artistDetailReadinessObserver) private var readinessObserver
    let artistID: UUID
    @State private var artist: LibraryArtistProjection?
    @State private var releases = ArtistReleaseSections.empty
    @State private var tracks: [LibraryTrackProjection] = []
    @State private var tracksClock = TrackTableContentClock()
    @State private var isLoading = true
    @State private var loadFailure: String?
    @State private var loadGeneration = 0
    @State private var isEditorPresented = false

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
                            ),
                            scrollOwnership: .page
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
            if loadFailure == nil {
                readinessObserver?.notify(artistID)
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            if let artist {
                CatalogEntityEditorSheet(
                    model: model,
                    title: "Edit Artist",
                    fieldLabel: "Artist Name",
                    initialValue: artist.name,
                    descriptionFieldLabel: "Artist Description",
                    initialDescription: artist.userDescription,
                    artworkTarget: .managedArtist(artist.id),
                    artworkLabel: "Artist Image"
                ) { name, userDescription in
                    guard let updated = await model.updateProductionArtist(
                        id: artist.id,
                        name: name,
                        userDescription: userDescription
                    ) else {
                        return false
                    }
                    self.artist = updated
                    return true
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
                ),
                scrollOwnership: .page
            )
        }
    }

    private func albumGrid(
        _ albums: [LibraryAlbumProjection]
    ) -> some View {
        LazyVGrid(
            columns: CatalogCardLayoutMetrics.layoutColumns(
                spacing: 16,
                size: catalogCardSize
            ),
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
        .frame(maxWidth: .infinity)
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
                VStack(
                    alignment: .leading,
                    spacing: CatalogDetailHeaderMetrics.eyebrowTitleSpacing
                ) {
                    CatalogDetailEyebrow("ARTIST")
                    Text(artist.name)
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .fixedSize(horizontal: false, vertical: true)
                if let userDescription = artist.userDescription {
                    Text(userDescription)
                        .font(.callout)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(
                    "\(artist.albumCount) albums · \(artist.trackCount) tracks"
                )
                .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    playbackActions(artist)
                    artistFavoriteButton(artist)
                    Spacer(minLength: 16)
                    editButton
                    actionsMenu(artist)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var editButton: some View {
        Button("Edit", systemImage: "pencil") {
            isEditorPresented = true
        }
        .buttonStyle(.bordered)
    }

    private func actionsMenu(
        _ artist: LibraryArtistProjection
    ) -> some View {
        Menu {
            artistActions(artist)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .help("Artist Actions")
    }

    private func artistFavoriteButton(
        _ artist: LibraryArtistProjection
    ) -> some View {
        FavoriteButton(
            itemID: artist.id,
            isFavorite: artist.isFavorite,
            itemName: artist.name,
            controlSize: 34
        ) { requestedValue in
            guard let updated = await model.setProductionArtistFavorite(
                artist,
                isFavorite: requestedValue
            ) else {
                return false
            }
            self.artist = updated
            return true
        }
        .imageScale(.large)
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
        }
    }

    @ViewBuilder
    private func artistActions(
        _ artist: LibraryArtistProjection
    ) -> some View {
        FavoriteContextMenuItem(isFavorite: artist.isFavorite) {
            Task {
                guard let updated = await model.setProductionArtistFavorite(
                    artist,
                    isFavorite: !artist.isFavorite
                ) else {
                    return
                }
                self.artist = updated
            }
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
        FavoriteContextMenuItem(isFavorite: album.isFavorite) {
            Task {
                guard await model.setProductionAlbumFavorite(
                    album,
                    isFavorite: !album.isFavorite
                ) != nil else {
                    return
                }
                if let updated = try? await store.artistReleaseSections(
                    artistID: artistID
                ) {
                    releases = updated
                }
            }
        }
        Divider()
        QuickAlbumTagMenuItems(
            store: store,
            albumID: album.id
        )
        AddAlbumToPlaylistMenuItems(
            store: store,
            albumID: album.id
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

// swiftlint:enable file_length
