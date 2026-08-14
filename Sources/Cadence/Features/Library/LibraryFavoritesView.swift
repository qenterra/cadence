import SwiftUI

struct LibraryFavoritesView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @AppStorage("library.favoriteSection")
    private var sectionRawValue = FavoriteCatalogSection.songs.rawValue
    @State private var selection: Set<UUID> = []

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
    }

    private var header: some View {
        CadencePageHeader(
            "Favorites",
            subtitle: "\(favoriteCount) saved"
        ) {
            if section == .songs, !store.favoriteTracks.isEmpty {
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
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var sectionPicker: some View {
        Picker("Favorite Type", selection: sectionBinding) {
            ForEach(FavoriteCatalogSection.allCases) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
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
        if store.favoriteTracks.isEmpty {
            emptyState(
                title: "No Favorite Tracks",
                description: "Tracks you favorite will appear here."
            )
        } else {
            ProductionTrackTable(
                model: model,
                tracks: store.favoriteTracks,
                queueSource: .favorites,
                onReachEnd: {
                    await store.loadNextFavoriteTracks()
                },
                selection: $selection
            )
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
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
                            album: album
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
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
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
                            artist: artist
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
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
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
        store.favoriteTracks.count
            + store.favoriteAlbums.count
            + store.favoriteArtists.count
    }

    private var catalogGrid: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 160, maximum: 220),
                spacing: 18
            ),
        ]
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
