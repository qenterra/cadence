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
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
            }
        }
        .background(CadenceTheme.contentBackground)
    }
}

private extension ProductionSearchResultsView {
    private var header: some View {
        CadencePageHeader(
            "Search",
            subtitle: "Results for “\(store.catalogSearchQuery)”"
        )
    }

    @ViewBuilder
    private var artistsSection: some View {
        if !store.catalogSearchResults.artists.isEmpty {
            resultSection("Artists") {
                resultGrid {
                    ForEach(store.catalogSearchResults.artists) { artist in
                        mediaResultRow(
                            ProductionSearchMediaResult(
                                title: artist.name,
                                subtitle: "\(artist.albumCount) albums · \(artist.trackCount) tracks",
                                artworkID: artist.customArtworkID,
                                placeholder: .artist
                            ),
                            action: {
                                model.requestOpenProductionArtistContextually(
                                    id: artist.id
                                )
                            },
                            actions: {
                                artistActions(artist)
                            }
                        )
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
                        mediaResultRow(
                            ProductionSearchMediaResult(
                                title: album.title,
                                subtitle: album.artist,
                                artworkID: album.customArtworkID,
                                placeholder: .album
                            ),
                            action: {
                                model.requestOpenProductionAlbumContextually(
                                    id: album.id
                                )
                            },
                            actions: {
                                albumActions(album)
                            }
                        )
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
                GridItem(
                    .adaptive(minimum: 260, maximum: 420),
                    spacing: 12
                ),
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

    private func mediaResultRow(
        _ result: ProductionSearchMediaResult,
        action: @escaping () -> Void,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    ProductionArtworkView(
                        model: model,
                        artworkID: result.artworkID,
                        title: result.title,
                        placeholder: result.placeholder,
                        cornerRadius: result.placeholder == .artist ? 20 : 8
                    )
                    .frame(width: 40, height: 40)
                    .clipShape(
                        result.placeholder == .artist
                            ? AnyShape(Circle())
                            : AnyShape(RoundedRectangle(cornerRadius: 8))
                    )

                    resultLabels(
                        title: result.title,
                        subtitle: result.subtitle
                    )
                    Spacer(minLength: 8)
                }
                .padding(.leading, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu(content: actions) {
                Image(systemName: "ellipsis")
                    .frame(width: 30, height: 30)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .padding(.trailing, 8)
            .help("More Actions")
        }
        .background(CadenceTheme.subduedFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

private struct ProductionSearchMediaResult {
    let title: String
    let subtitle: String
    let artworkID: UUID?
    let placeholder: ArtworkPlaceholder
}
