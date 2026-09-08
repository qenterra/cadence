import AppKit
import QenTerraMediaComponents
import SwiftUI

struct ProductionArtistsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @Environment(\.catalogCardSize) private var catalogCardSize
    @AppStorage("artists.sortField") private var sortFieldRaw = ArtistSortField.name.rawValue
    @AppStorage("artists.sortDescending") private var sortsDescending = false

    var body: some View {
        Group {
            if let artistID = model.selectedProductionArtistID {
                ProductionArtistDetailView(
                    model: model,
                    store: store,
                    artistID: artistID
                )
            } else if store.artists.isEmpty {
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
                            ForEach(sortedArtists) { artist in
                                artistTile(artist)
                                    .padding(.bottom, 6)
                            }
                        }

                        if store.canLoadMoreArtists {
                            ProgressView("Loading More Artists")
                                .frame(maxWidth: .infinity)
                                .task(id: store.artists.last?.id) {
                                    await store.loadNextArtists()
                                }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
                .refreshable {
                    await store.refresh(.artists)
                }
            }
        }
        .background(CadenceTheme.contentBackground)
    }

    @ViewBuilder
    private var emptyContent: some View {
        if store.availability == .loading {
            ProgressView("Loading Artists")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyLibraryView(
                title: "No Artists Yet",
                description: "Artists will appear here after you import music."
            ) {
                model.requestNavigationDestination(.importMusic)
            }
        }
    }

    private var header: some View {
        CadencePageHeader(
            "Artists",
            subtitle: "\(store.artists.count) artists"
        ) {
            CatalogSortMenu(
                label: "Sort Artists",
                fields: artistSortFields,
                selection: artistSortSelection,
                fieldTitle: \ArtistSortField.title
            )
        }
    }

    private var artistSortSelection: Binding<
        CatalogSortSelection<ArtistSortField>
    > {
        Binding(
            get: {
                CatalogSortSelection(
                    field: ArtistSortField(rawValue: sortFieldRaw) ?? .name,
                    direction: sortsDescending ? .descending : .ascending
                )
            },
            set: { selection in
                sortFieldRaw = selection.field.rawValue
                sortsDescending = selection.direction == .descending
            }
        )
    }

    private var sortedArtists: [LibraryArtistProjection] {
        let field = ArtistSortField(rawValue: sortFieldRaw) ?? .name
        return store.artists.sorted(by: { lhs, rhs in
            let comparison: ComparisonResult = switch field {
            case .name:
                lhs.name.localizedStandardCompare(rhs.name)
            case .recentlyPlayed:
                lhs.name.localizedStandardCompare(rhs.name)
            case .albumCount:
                comparison(of: lhs.albumCount, and: rhs.albumCount)
            case .trackCount:
                comparison(of: lhs.trackCount, and: rhs.trackCount)
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

    private var artistSortFields: [ArtistSortField] {
        ArtistSortField.allCases.filter { $0 != .recentlyPlayed }
    }

    private func comparison(of lhs: Int, and rhs: Int) -> ComparisonResult {
        if lhs == rhs {
            return .orderedSame
        }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private func artistTile(
        _ artist: LibraryArtistProjection
    ) -> some View {
        ProductionArtistTile(
            model: model,
            store: store,
            artist: artist,
            orderedTargets: sortedArtists.map {
                CatalogActivationTarget(kind: .artist, id: $0.id)
            }
        )
    }
}

struct ProductionArtistTile: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let artist: LibraryArtistProjection
    let orderedTargets: [CatalogActivationTarget]
    @State private var isRenamePresented = false
    @State private var renameDraft = ""

    var body: some View {
        MediaTile(
            item: CadenceMediaAdapters.mediaItem(
                id: artist.id,
                title: artist.name,
                subtitle: "",
                metadata: "\(artist.albumCount) albums · \(artist.trackCount) tracks",
                isSelected: model.catalogActivationSelection.contains(
                    CatalogActivationTarget(kind: .artist, id: artist.id)
                )
            ),
            accessibilityLabel: "Open \(artist.name)",
            presentation: .cadenceCatalog(metadataStyle: .secondary)
        ) {
            ProductionArtworkView(
                model: model,
                artworkID: artist.customArtworkID,
                title: artist.name,
                placeholder: .artist,
                cornerRadius: CadenceTheme.radiusNone,
                showsBorder: false
            )
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
            }
        } trailingAccessory: { context in
            FavoriteButton(
                itemID: artist.id,
                isFavorite: artist.isFavorite,
                itemName: artist.name,
                controlSize: CatalogTileFavoriteLayout.controlSize,
                isRevealed: false,
                interactionContext: context
            ) { requestedValue in
                await model.setProductionArtistFavorite(
                    artist,
                    isFavorite: requestedValue
                ) != nil
            }
        } action: {
            openArtist()
        }
        .contextMenu {
            artistActions
        }
        .catalogRenameAlert(
            "Rename Artist",
            prompt: "Artist Name",
            isPresented: $isRenamePresented,
            draft: $renameDraft
        ) { name in
            Task {
                _ = await model.renameProductionArtist(
                    id: artist.id,
                    name: name
                )
            }
        }
    }

    @ViewBuilder
    private var artistActions: some View {
        Button(
            artist.isFavorite ? "Remove from Favorites" : "Add to Favorites",
            systemImage: artist.isFavorite ? "heart.slash" : "heart"
        ) {
            Task {
                await model.setProductionArtistFavorite(
                    artist,
                    isFavorite: !artist.isFavorite
                )
            }
        }
        Button("Rename", systemImage: "pencil") {
            beginRename()
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

    private func beginRename() {
        renameDraft = artist.name
        isRenamePresented = true
    }

    private func openArtist() {
        let target = CatalogActivationTarget(kind: .artist, id: artist.id)
        let action = model.handleCatalogSelection(
            target,
            orderedTargets: orderedTargets,
            modifiers: NSApp.currentEvent?.modifierFlags ?? []
        )
        guard action == .activate else {
            return
        }
        model.requestOpenProductionArtistContextually(id: artist.id)
    }
}
