import AppKit
import QenTerraMediaComponents
import SwiftUI

struct ProductionAlbumsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @Environment(\.catalogCardSize) private var catalogCardSize
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

                        let range = CatalogCardLayoutMetrics.widthRange(
                            for: catalogCardSize
                        )
                        MediaGrid(
                            minimumWidth: range.lowerBound,
                            maximumWidth: range.upperBound,
                            spacing: 18,
                            honorsExplicitSizing: true
                        ) {
                            ForEach(sortedAlbums) { album in
                                albumTile(album)
                                    .padding(.bottom, 6)
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
            CatalogSortMenu(
                label: "Sort Albums",
                fields: Array(AlbumSortField.allCases),
                selection: albumSortSelection,
                fieldTitle: \AlbumSortField.title
            )
        }
    }

    private var albumSortSelection: Binding<
        CatalogSortSelection<AlbumSortField>
    > {
        Binding(
            get: {
                CatalogSortSelection(
                    field: AlbumSortField(rawValue: sortFieldRaw) ?? .artist,
                    direction: sortsDescending ? .descending : .ascending
                )
            },
            set: { selection in
                sortFieldRaw = selection.field.rawValue
                sortsDescending = selection.direction == .descending
            }
        )
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
            album: album,
            orderedTargets: sortedAlbums.map {
                CatalogActivationTarget(kind: .album, id: $0.id)
            }
        )
    }
}

struct ProductionAlbumTile: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let album: LibraryAlbumProjection
    let orderedTargets: [CatalogActivationTarget]
    @State private var isRenamePresented = false
    @State private var renameDraft = ""

    var body: some View {
        MediaTile(
            item: CadenceMediaAdapters.mediaItem(
                id: album.id,
                title: album.title,
                subtitle: album.artist,
                metadata: albumDetail(album),
                isSelected: model.catalogActivationSelection.contains(
                    CatalogActivationTarget(kind: .album, id: album.id)
                )
            ),
            accessibilityLabel: "Open \(album.title), \(album.artist)",
            presentation: .cadenceCatalog(contentSpacing: 9)
        ) {
            ProductionArtworkView(
                model: model,
                artworkID: album.customArtworkID,
                title: album.title,
                placeholder: .album,
                cornerRadius: CadenceTheme.radiusGroup
            )
        } trailingAccessory: { context in
            FavoriteButton(
                itemID: album.id,
                isFavorite: album.isFavorite,
                itemName: album.title,
                controlSize: CatalogTileFavoriteLayout.controlSize,
                isRevealed: false,
                interactionContext: context
            ) { requestedValue in
                await model.setProductionAlbumFavorite(
                    album,
                    isFavorite: requestedValue
                ) != nil
            }
        } action: {
            openAlbum()
        }
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
        let action = model.handleCatalogSelection(
            target,
            orderedTargets: orderedTargets,
            modifiers: NSApp.currentEvent?.modifierFlags ?? []
        )
        guard action == .activate else {
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
