import SwiftUI

struct LibraryFavoritesView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @AppStorage("library.favoriteSection")
    private var sectionRawValue = FavoriteCatalogSection.songs.rawValue
    @State private var selection: Set<UUID> = []
    @State private var favoriteSort = LibraryTrackSort.titleAscending

    var body: some View {
        VStack(spacing: 0) {
            header
            sectionPicker
            content
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(CadenceTheme.contentBackground)
        .task(id: favoriteWindowConfigurationID) {
            await store.favoriteTracksWindow?.configure(
                totalCount: store.favoriteTrackIDs.count,
                query: LibraryTrackQuery(
                    scope: .favorites,
                    sort: favoriteSort
                ),
                contentVersion: store.allTracksWindowContentVersion
            )
        }
    }

    private var header: some View {
        CadencePageHeader(
            "Favorites",
            subtitle: "\(favoriteCount) saved"
        ) {
            if section == .songs, !store.favoriteTrackIDs.isEmpty {
                Button("Shuffle", systemImage: "shuffle") {
                    guard let track = store.favoriteTracks.randomElement() else {
                        return
                    }
                    model.playProductionTrack(
                        track,
                        within: store.favoriteTracks,
                        source: .favorites,
                        isShuffled: true
                    )
                }
                Button("Play", systemImage: "play.fill") {
                    guard let track = store.favoriteTracks.first else {
                        return
                    }
                    model.playProductionTrack(
                        track,
                        within: store.favoriteTracks,
                        source: .favorites
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, CadenceLayout.pageInset)
        .padding(.top, CadenceLayout.pageInset)
        .padding(.bottom, CadenceLayout.contentGap)
    }

    private var sectionPicker: some View {
        Picker("Type", selection: sectionBinding) {
            ForEach(FavoriteCatalogSection.allCases) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Favorite Type")
        .padding(.horizontal, CadenceLayout.pageInset)
        .padding(.bottom, CadenceLayout.contentGap)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .songs:
            favoriteSongs
        case .albums:
            favoriteAlbums
        case .artists:
            favoriteArtists
        }
    }

    @ViewBuilder
    private var favoriteSongs: some View {
        if store.favoriteTrackIDs.isEmpty {
            emptyState(
                title: "No Favorite Tracks",
                description: "Tracks you favorite will appear here."
            )
        } else if let window = store.favoriteTracksWindow {
            favoriteWindowContent(window)
        } else {
            ProductionTrackTable(
                model: model,
                tracks: store.favoriteTracks,
                contentVersion: store.favoriteTracksVersion,
                queueSource: .favorites,
                onReachEnd: {
                    await store.loadNextFavoriteTracks()
                },
                selection: $selection,
                refreshAction: {
                    await store.refresh(.favorites)
                }
            )
            .padding(.bottom, CadenceLayout.pageInset)
        }
    }

    @ViewBuilder
    private func favoriteWindowContent(
        _ window: LibraryTrackWindow
    ) -> some View {
        switch window.firstPageState {
        case .idle, .loading:
            ProgressView("Loading Favorite Tracks")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView(
                "Couldn’t Load Favorite Tracks",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            .overlay(alignment: .bottom) {
                Button("Try Again") {
                    Task {
                        await window.retryFirstPage()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, CadenceLayout.sectionGap)
            }
        case .ready:
            ProductionTrackTable(
                model: model,
                tracks: [],
                contentVersion: nil,
                queueSource: .favorites,
                virtualWindow: window,
                repositorySortAction: { sort in
                    favoriteSort = sort
                },
                selection: $selection,
                refreshAction: {
                    await store.refresh(.favorites)
                }
            )
            .padding(.bottom, CadenceLayout.pageInset)
        }
    }

    @ViewBuilder
    private var favoriteAlbums: some View {
        if store.favoriteAlbums.isEmpty {
            emptyState(
                title: "No Favorite Albums",
                description: "Albums you favorite will appear here."
            )
        } else {
            ScrollView(.vertical) {
                LazyVGrid(columns: catalogGrid, alignment: .leading, spacing: 24) {
                    ForEach(store.favoriteAlbums) { album in
                        ProductionAlbumTile(
                            model: model,
                            store: store,
                            album: album,
                            orderedTargets: store.favoriteAlbums.map {
                                CatalogActivationTarget(
                                    kind: .album,
                                    id: $0.id
                                )
                            }
                        )
                    }

                    if store.canLoadMoreFavoriteAlbums {
                        ProgressView("Loading More Albums")
                            .frame(maxWidth: .infinity)
                            .task(id: store.favoriteAlbums.last?.id) {
                                await store.loadNextFavoriteAlbums()
                            }
                    }
                }
                .padding(.horizontal, CadenceLayout.pageInset)
                .padding(.bottom, CadenceLayout.pageInset)
            }
            .refreshable {
                await store.refresh(.favorites)
            }
        }
    }

    @ViewBuilder
    private var favoriteArtists: some View {
        if store.favoriteArtists.isEmpty {
            emptyState(
                title: "No Favorite Artists",
                description: "Artists you favorite will appear here."
            )
        } else {
            ScrollView(.vertical) {
                LazyVGrid(columns: catalogGrid, alignment: .leading, spacing: 24) {
                    ForEach(store.favoriteArtists) { artist in
                        ProductionArtistTile(
                            model: model,
                            store: store,
                            artist: artist,
                            orderedTargets: store.favoriteArtists.map {
                                CatalogActivationTarget(
                                    kind: .artist,
                                    id: $0.id
                                )
                            }
                        )
                    }

                    if store.canLoadMoreFavoriteArtists {
                        ProgressView("Loading More Artists")
                            .frame(maxWidth: .infinity)
                            .task(id: store.favoriteArtists.last?.id) {
                                await store.loadNextFavoriteArtists()
                            }
                    }
                }
                .padding(.horizontal, CadenceLayout.pageInset)
                .padding(.bottom, CadenceLayout.pageInset)
            }
            .refreshable {
                await store.refresh(.favorites)
            }
        }
    }

    private var section: FavoriteCatalogSection {
        FavoriteCatalogSection(rawValue: sectionRawValue) ?? .songs
    }

    private var sectionBinding: Binding<FavoriteCatalogSection> {
        Binding(
            get: { section },
            set: { sectionRawValue = $0.rawValue }
        )
    }

    private var favoriteCount: Int {
        store.favoriteTrackIDs.count
            + store.favoriteAlbums.count
            + store.favoriteArtists.count
    }

    private var favoriteWindowConfigurationID:
        FavoriteWindowConfigurationID {
        FavoriteWindowConfigurationID(
            totalCount: store.favoriteTrackIDs.count,
            sort: favoriteSort,
            contentVersion: store.allTracksWindowContentVersion
        )
    }

    private var catalogGrid: [GridItem] {
        CatalogCardLayoutMetrics.layoutColumns(spacing: 18)
    }

    private func emptyState(
        title: String,
        description: String
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "heart",
            description: Text(description)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FavoriteWindowConfigurationID: Equatable {
    let totalCount: Int
    let sort: LibraryTrackSort
    let contentVersion: TrackTableContentVersion
}
