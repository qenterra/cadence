import SwiftUI

struct ProductionAlbumsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @AppStorage("albums.sortField") private var sortFieldRaw = AlbumSortField.artist.rawValue
    @AppStorage("albums.sortDescending") private var sortsDescending = false

    var body: some View {
        Group {
            if let albumID = model.selectedProductionAlbumID {
                ProductionAlbumDetailView(
                    model: model,
                    store: store,
                    albumID: albumID
                )
            } else if store.albums.isEmpty {
                emptyContent
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        header

                        LazyVGrid(
                            columns: CatalogCardLayoutMetrics.layoutColumns(
                                spacing: 18
                            ),
                            alignment: .leading,
                            spacing: 24
                        ) {
                            ForEach(sortedAlbums) { album in
                                albumTile(album)
                            }
                        }

                        if store.canLoadMoreAlbums {
                            ProgressView("Loading More Albums")
                                .frame(maxWidth: .infinity)
                                .task(id: store.albums.last?.id) {
                                    await store.loadNextAlbums()
                                }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
                .refreshable {
                    await store.refresh(.albums)
                }
            }
        }
        .background(CadenceTheme.contentBackground)
    }

    @ViewBuilder
    private var emptyContent: some View {
        if store.availability == .loading {
            ProgressView("Loading Albums")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyLibraryView(
                title: "No Albums Yet",
                description: "Albums will appear here after you import music."
            ) {
                model.requestNavigationDestination(.importMusic)
            }
        }
    }

    private var header: some View {
        CadencePageHeader(
            "Albums",
            subtitle: "\(store.albums.count) albums"
        ) {
            Menu {
                Picker("Sort Albums", selection: $sortFieldRaw) {
                    ForEach(AlbumSortField.allCases) { field in
                        Text(field.title).tag(field.rawValue)
                    }
                }
                Toggle("Descending", isOn: $sortsDescending)
            } label: {
                Label("Sort Albums", systemImage: "arrow.up.arrow.down.circle")
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var sortedAlbums: [LibraryAlbumProjection] {
        let field = AlbumSortField(rawValue: sortFieldRaw) ?? .artist
        return store.albums.sorted(by: { lhs, rhs in
            let comparison: ComparisonResult = switch field {
            case .artist:
                lhs.artist.localizedStandardCompare(rhs.artist)
            case .title:
                lhs.title.localizedStandardCompare(rhs.title)
            case .releaseYear:
                comparison(of: lhs.year ?? 0, and: rhs.year ?? 0)
            case .favoriteDate:
                (lhs.favoriteDate ?? .distantPast).compare(
                    rhs.favoriteDate ?? .distantPast
                )
            }
            return sortsDescending
                ? comparison == .orderedDescending
                : comparison == .orderedAscending
        })
    }

    private func comparison(of lhs: Int, and rhs: Int) -> ComparisonResult {
        if lhs == rhs {
            return .orderedSame
        }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private func albumTile(
        _ album: LibraryAlbumProjection
    ) -> some View {
        ProductionAlbumTile(
            model: model,
            store: store,
            album: album
        )
    }
}

struct ProductionAlbumTile: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let album: LibraryAlbumProjection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFavoriteFocused: Bool
    @State private var isHovered = false
    @State private var isRenamePresented = false
    @State private var renameDraft = ""

    var body: some View {
        VStack(alignment: .center, spacing: 9) {
            Button(action: openAlbum) {
                ProductionArtworkView(
                    model: model,
                    artworkID: album.customArtworkID,
                    title: album.title,
                    placeholder: .album,
                    cornerRadius: CadenceTheme.radiusGroup
                )
                .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.plain)

            ZStack {
                Button(action: openAlbum) {
                    Text(album.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(
                .horizontal,
                CatalogTileFavoriteLayout.titleHorizontalInset
            )
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                FavoriteButton(
                    itemID: album.id,
                    isFavorite: album.isFavorite,
                    itemName: album.title,
                    controlSize: CatalogTileFavoriteLayout.controlSize
                ) { requestedValue in
                    await model.setProductionAlbumFavorite(
                        album,
                        isFavorite: requestedValue
                    ) != nil
                }
                .focused($isFavoriteFocused)
                .opacity(favoritePresentation.visualOpacity)
                .allowsHitTesting(favoritePresentation.acceptsPointerInteraction)
                .accessibilityHidden(!favoritePresentation.isAccessibilityVisible)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeOut(duration: CadenceTheme.motionHover),
                    value: favoritePresentation.visualOpacity
                )
            }

            Text(album.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Text(albumDetail(album))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .padding(10)
        .frame(width: CatalogCardLayoutMetrics.cardWidth)
        .background {
            BrowserRowSurface(
                isSelected: model.catalogActivationSelection.selected
                    == CatalogActivationTarget(kind: .album, id: album.id),
                isHovered: isHovered,
                isFocused: false
            )
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            albumActions
        }
        .catalogRenameAlert(
            "Rename Album",
            prompt: "Album Name",
            isPresented: $isRenamePresented,
            draft: $renameDraft
        ) { title in
            Task {
                _ = await model.renameProductionAlbum(
                    id: album.id,
                    title: title
                )
            }
        }
    }

    private var favoritePresentation: FavoriteControlPresentation {
        FavoriteControlPresentation.resolve(
            isHovered: isHovered,
            isFocused: isFavoriteFocused
        )
    }

    @ViewBuilder
    private var albumActions: some View {
        Button(
            album.isFavorite ? "Remove from Favorites" : "Add to Favorites",
            systemImage: album.isFavorite ? "heart.slash" : "heart"
        ) {
            Task {
                await model.setProductionAlbumFavorite(
                    album,
                    isFavorite: !album.isFavorite
                )
            }
        }
        Button("Rename", systemImage: "pencil") {
            beginRename()
        }
        Button(
            HomePinStore.contains(album.id, in: .album)
                ? "Unpin from Home"
                : "Pin to Home",
            systemImage: HomePinStore.contains(album.id, in: .album)
                ? "pin.slash"
                : "pin"
        ) {
            HomePinStore.toggle(album.id, in: .album)
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

    private func beginRename() {
        renameDraft = album.title
        isRenamePresented = true
    }

    private func openAlbum() {
        let target = CatalogActivationTarget(kind: .album, id: album.id)
        guard model.requestCatalogActivation(target) else {
            return
        }
        model.requestOpenProductionAlbumContextually(id: album.id)
    }

    private func albumDetail(
        _ album: LibraryAlbumProjection
    ) -> String {
        var parts = ["\(album.trackCount) tracks"]
        if let year = album.year {
            parts.append(year.formatted(.number.grouping(.never)))
        }
        return parts.joined(separator: " · ")
    }
}
