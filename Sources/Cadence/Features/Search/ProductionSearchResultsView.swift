import SwiftUI

struct ProductionSearchResultsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore

    var body: some View {
        Group {
            if store.isCatalogSearching, store.catalogSearchResults.isEmpty {
                ProgressView("Searching Library")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.catalogSearchResults.isEmpty {
                ContentUnavailableView.search(
                    text: store.catalogSearchQuery
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        header
                        artistsSection
                        albumsSection
                        tagsSection
                        tracksSection
                    }
                    .padding(28)
                }
            }
        }
        .background(CadenceTheme.contentBackground)
    }
}

private extension ProductionSearchResultsView {
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Search")
                .font(.largeTitle.bold())
            Text("Results for “\(store.catalogSearchQuery)”")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var artistsSection: some View {
        if !store.catalogSearchResults.artists.isEmpty {
            resultSection("Artists") {
                resultGrid {
                    ForEach(store.catalogSearchResults.artists) { artist in
                        mediaResultButton(
                            title: artist.name,
                            subtitle: "\(artist.albumCount) albums · \(artist.trackCount) tracks",
                            artworkID: artist.customArtworkID,
                            placeholder: .artist
                        ) {
                            model.requestOpenProductionArtistContextually(
                                id: artist.id
                            )
                        }
                        .overlay(alignment: .trailing) {
                            mediaActionsMenu {
                                artistActions(artist)
                            }
                        }
                        .contextMenu {
                            artistActions(artist)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var albumsSection: some View {
        if !store.catalogSearchResults.albums.isEmpty {
            resultSection("Albums") {
                resultGrid {
                    ForEach(store.catalogSearchResults.albums) { album in
                        mediaResultButton(
                            title: album.title,
                            subtitle: album.artist,
                            artworkID: album.customArtworkID,
                            placeholder: .album
                        ) {
                            model.requestOpenProductionAlbumContextually(
                                id: album.id
                            )
                        }
                        .overlay(alignment: .trailing) {
                            mediaActionsMenu {
                                albumActions(album)
                            }
                        }
                        .contextMenu {
                            albumActions(album)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !store.catalogSearchResults.tags.isEmpty {
            resultSection("Tags") {
                resultGrid {
                    ForEach(store.catalogSearchResults.tags) { tag in
                        resultButton(
                            title: tag.displayPath,
                            subtitle: tag.groupPath ?? "Standalone",
                            symbol: "tag.fill"
                        ) {
                            model.requestOpenProductionTagContextually(
                                id: tag.id
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tracksSection: some View {
        if !store.catalogSearchResults.tracks.isEmpty {
            resultSection("Tracks") {
                ProductionTrackList(
                    model: model,
                    tracks: store.catalogSearchResults.tracks
                )
            }
        }
    }

    private func resultSection(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }

    private func resultGrid(
        @ViewBuilder content: () -> some View
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 220), spacing: 12),
            ],
            alignment: .leading,
            spacing: 12
        ) {
            content()
        }
    }

    private func resultButton(
        title: String,
        subtitle: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(CadenceTheme.subduedFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                resultLabels(title: title, subtitle: subtitle)
                Spacer()
            }
            .padding(12)
            .background(CadenceTheme.hoverFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mediaResultButton(
        title: String,
        subtitle: String,
        artworkID: UUID?,
        placeholder: ArtworkPlaceholder,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ProductionArtworkView(
                    model: model,
                    artworkID: artworkID,
                    title: title,
                    placeholder: placeholder,
                    cornerRadius: placeholder == .artist ? 17 : 8
                )
                .frame(width: 34, height: 34)
                .clipShape(
                    placeholder == .artist
                        ? AnyShape(Circle())
                        : AnyShape(RoundedRectangle(cornerRadius: 8))
                )

                resultLabels(title: title, subtitle: subtitle)
                Spacer()
            }
            .padding(12)
            .background(CadenceTheme.hoverFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mediaActionsMenu(
        @ViewBuilder content: () -> some View
    ) -> some View {
        Menu(content: content) {
            Image(systemName: "ellipsis")
                .frame(width: 30, height: 30)
        }
        .menuIndicator(.hidden)
        .padding(.trailing, 10)
        .help("More Actions")
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

    private func resultLabels(
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
