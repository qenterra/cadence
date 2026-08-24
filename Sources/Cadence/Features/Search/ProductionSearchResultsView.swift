import SwiftUI

struct ProductionSearchResultsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @State private var expandedGroup: CatalogSearchGroup?

    var body: some View {
        Group {
            if store.isCatalogSearching, store.catalogSearchResults.isEmpty {
                ProgressView("Searching Library")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.catalogSearchResults.isEmpty,
                      case let .failed(message) = store.lyricsSearchIndexState {
                ContentUnavailableView(
                    "Lyrics Search Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.catalogSearchResults.isEmpty {
                ContentUnavailableView.search(
                    text: store.catalogSearchQuery
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if expandedGroup == .tracks {
                expandedTracks
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        header
                        searchSections
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
            }
        }
        .background(CadenceTheme.contentBackground)
        .onChange(of: store.catalogSearchQuery) {
            expandedGroup = nil
        }
    }
}

private extension ProductionSearchResultsView {
    private var expandedTracks: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ProductionTrackTable(
                model: model,
                tracks: store.catalogSearchResults.tracks,
                contentVersion: store.catalogSearchTracksVersion,
                context: .search(store.catalogSearchQuery),
                onReachEnd: {
                    await store.loadNextCatalogSearchGroup(.tracks)
                }
            )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    private var header: some View {
        CadencePageHeader(
            expandedGroup == nil ? "Search" : expandedTitle,
            subtitle: "Results for “\(store.catalogSearchQuery)”"
        ) {
            if expandedGroup != nil {
                Button("All Results", systemImage: "chevron.backward") {
                    expandedGroup = nil
                }
            }
        }
    }

    @ViewBuilder
    private var searchSections: some View {
        switch expandedGroup {
        case .artists:
            artistsSection
        case .albums:
            albumsSection
        case .tags:
            tagsSection
        case .tracks:
            tracksSection
        case .lyrics:
            lyricsSection
        case nil:
            artistsSection
            albumsSection
            tagsSection
            tracksSection
            lyricsSection
        }
    }

    private var expandedTitle: String {
        switch expandedGroup {
        case .artists: "Artists"
        case .albums: "Albums"
        case .tags: "Tags"
        case .tracks: "Tracks"
        case .lyrics: "Lyrics"
        case nil: "Search"
        }
    }

    @ViewBuilder
    private var artistsSection: some View {
        if !store.catalogSearchResults.artists.isEmpty {
            resultSection(
                "Artists",
                group: .artists,
                count: store.catalogSearchResults.artists.count
            ) {
                resultGrid {
                    ForEach(store.catalogSearchResults.artists) { artist in
                        mediaResultRow(
                            ProductionSearchMediaResult(
                                title: artist.name,
                                subtitle: "\(artist.albumCount) albums · \(artist.trackCount) tracks",
                                artworkID: artist.customArtworkID,
                                placeholder: .artist
                            ),
                            isSelected: isCatalogResultSelected(
                                kind: .artist,
                                id: artist.id
                            ),
                            action: {
                                guard model.requestCatalogActivation(
                                    CatalogActivationTarget(
                                        kind: .artist,
                                        id: artist.id
                                    )
                                ) else { return }
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
                        .task {
                            guard
                                expandedGroup == .artists,
                                artist.id
                                == store.catalogSearchResults.artists.last?.id
                            else {
                                return
                            }
                            await store.loadNextCatalogSearchGroup(.artists)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var albumsSection: some View {
        if !store.catalogSearchResults.albums.isEmpty {
            resultSection(
                "Albums",
                group: .albums,
                count: store.catalogSearchResults.albums.count
            ) {
                resultGrid {
                    ForEach(store.catalogSearchResults.albums) { album in
                        mediaResultRow(
                            ProductionSearchMediaResult(
                                title: album.title,
                                subtitle: album.artist,
                                artworkID: album.customArtworkID,
                                placeholder: .album
                            ),
                            isSelected: isCatalogResultSelected(
                                kind: .album,
                                id: album.id
                            ),
                            action: {
                                guard model.requestCatalogActivation(
                                    CatalogActivationTarget(
                                        kind: .album,
                                        id: album.id
                                    )
                                ) else { return }
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
                        .task {
                            guard
                                expandedGroup == .albums,
                                album.id
                                == store.catalogSearchResults.albums.last?.id
                            else {
                                return
                            }
                            await store.loadNextCatalogSearchGroup(.albums)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !store.catalogSearchResults.tags.isEmpty {
            resultSection(
                "Tags",
                group: .tags,
                count: store.catalogSearchResults.tags.count
            ) {
                resultGrid {
                    ForEach(store.catalogSearchResults.tags) { tag in
                        resultButton(
                            title: tag.displayPath,
                            subtitle: tag.groupPath ?? "Standalone",
                            symbol: "tag.fill",
                            isSelected: isCatalogResultSelected(
                                kind: .tag,
                                id: tag.id
                            )
                        ) {
                            guard model.requestCatalogActivation(
                                CatalogActivationTarget(kind: .tag, id: tag.id)
                            ) else { return }
                            model.requestOpenProductionTagContextually(
                                id: tag.id
                            )
                        }
                        .task {
                            guard
                                expandedGroup == .tags,
                                tag.id == store.catalogSearchResults.tags.last?.id
                            else {
                                return
                            }
                            await store.loadNextCatalogSearchGroup(.tags)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tracksSection: some View {
        if !store.catalogSearchResults.tracks.isEmpty {
            resultSection(
                "Tracks",
                group: .tracks,
                count: store.catalogSearchResults.tracks.count
            ) {
                ProductionTrackTable(
                    model: model,
                    tracks: store.catalogSearchResults.tracks,
                    contentVersion: store.catalogSearchTracksVersion,
                    context: .search(store.catalogSearchQuery),
                    onReachEnd: expandedGroup == .tracks ? {
                        await store.loadNextCatalogSearchGroup(.tracks)
                    } : nil
                )
                .frame(
                    height: min(
                        max(
                            CGFloat(
                                store.catalogSearchResults.tracks.count * 58
                                    + 38
                            ),
                            240
                        ),
                        520
                    )
                )
            }
        }
    }

    private var lyricsSection: some View {
        LyricsSearchResultsSection(
            model: model,
            store: store
        )
    }

    private func resultSection(
        _ title: String,
        group: CatalogSearchGroup,
        count: Int,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.bold())
                Text(resultCount(count, group: group))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if expandedGroup == nil,
                   store.catalogSearchResults.hasMore(group) {
                    Button("See All") {
                        expandedGroup = group
                    }
                }
            }
            content()
        }
    }

    private func resultCount(
        _ count: Int,
        group: CatalogSearchGroup
    ) -> String {
        store.catalogSearchResults.hasMore(group)
            ? "Showing \(count)+"
            : count.formatted()
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
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(CadenceTheme.subduedFill)
                    .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusControl))

                resultLabels(title: title, subtitle: subtitle)
                Spacer()
            }
            .padding(12)
            .background {
                BrowserRowSurface(
                    isSelected: isSelected,
                    isHovered: false,
                    isFocused: false
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mediaResultRow(
        _ result: ProductionSearchMediaResult,
        isSelected: Bool,
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
                            : AnyShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusControl))
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
        .background {
            BrowserRowSurface(
                isSelected: isSelected,
                isHovered: false,
                isFocused: false
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup))
    }

    private func isCatalogResultSelected(
        kind: CatalogActivationKind,
        id: UUID
    ) -> Bool {
        model.catalogActivationSelection.selected
            == CatalogActivationTarget(kind: kind, id: id)
    }
}
