import SwiftUI

extension ProductionHomeView {
    @ViewBuilder
    var favorites: some View {
        let budget = HomeFavoritesPreviewBudget.resolve(
            trackCount: store.favoriteTracks.count,
            albumCount: store.favoriteAlbums.count,
            artistCount: store.favoriteArtists.count,
            limit: 6
        )
        let tracks = HomeListeningSelection.items(
            store.favoriteTracks,
            limit: budget.trackLimit
        )
        let albums = HomeListeningSelection.items(
            store.favoriteAlbums,
            limit: budget.albumLimit
        )
        let artists = HomeListeningSelection.items(
            store.favoriteArtists,
            limit: budget.artistLimit
        )

        if !tracks.isEmpty || !albums.isEmpty || !artists.isEmpty {
            HomeShelf(
                title: "Favorites",
                actionTitle: "See All",
                action: openFavorites
            ) {
                HomeCompactGrid {
                    ForEach(tracks) { track in
                        HomeTrackTile(
                            model: model,
                            track: track,
                            queue: store.favoriteTracks,
                            queueSource: .favorites
                        )
                    }

                    ForEach(albums) { album in
                        HomeAlbumTile(model: model, album: album)
                    }

                    ForEach(artists) { artist in
                        HomeDestinationTile(
                            model: model,
                            title: artist.name,
                            subtitle: "Artist",
                            artworkID: artist.customArtworkID,
                            placeholder: .artist
                        ) {
                            model.requestOpenProductionArtistContextually(
                                id: artist.id
                            )
                        }
                    }
                }
            }
        }
    }

    var pinnedItems: some View {
        pinnedItemsContent
            .id(pinRevision)
    }

    @ViewBuilder
    private var pinnedItemsContent: some View {
        let albums = pinnedAlbums
        let artists = pinnedArtists
        let playlists = pinnedPlaylists
        let smartCollections = pinnedSmartCollections

        if !albums.isEmpty || !artists.isEmpty || !playlists.isEmpty
            || !smartCollections.isEmpty {
            HomeShelf(title: "Quick Access") {
                HomeCompactGrid {
                    ForEach(albums) { album in
                        HomeAlbumTile(model: model, album: album)
                    }
                    ForEach(artists) { artist in
                        HomeDestinationTile(
                            model: model,
                            title: artist.name,
                            subtitle: "Artist",
                            artworkID: artist.customArtworkID,
                            placeholder: .artist
                        ) {
                            model.requestOpenProductionArtistContextually(
                                id: artist.id
                            )
                        }
                    }
                    ForEach(playlists) { playlist in
                        HomeDestinationTile(
                            model: model,
                            title: playlist.name,
                            subtitle: "\(playlist.trackCount) tracks",
                            artworkID: playlist.customArtworkID,
                            placeholder: .playlist
                        ) {
                            model.requestNavigationDestination(.playlists)
                            Task { await store.selectPlaylist(playlist.id) }
                        }
                    }
                    ForEach(smartCollections) { collection in
                        HomeDestinationTile(
                            model: model,
                            title: collection.name,
                            subtitle: "Smart Collection",
                            artworkID: collection.customArtworkID,
                            placeholder: .smartCollection
                        ) {
                            model.requestNavigationDestination(.smartCollections)
                            model.requestSelectSmartCollection(collection.id)
                        }
                    }
                }
            }
        }
    }

    private var pinnedAlbums: [LibraryAlbumProjection] {
        orderedPinnedItems(kind: .album, source: store.albums)
    }

    private var pinnedArtists: [LibraryArtistProjection] {
        orderedPinnedItems(kind: .artist, source: store.artists)
    }

    private var pinnedPlaylists: [LibraryPlaylistProjection] {
        orderedPinnedItems(kind: .playlist, source: store.playlists)
    }

    private var pinnedSmartCollections: [SmartCollectionPreview] {
        orderedPinnedItems(
            kind: .smartCollection,
            source: model.smartCollections
        )
    }

    var hasPinnedItems: Bool {
        !pinnedAlbums.isEmpty
            || !pinnedArtists.isEmpty
            || !pinnedPlaylists.isEmpty
            || !pinnedSmartCollections.isEmpty
    }

    private func orderedPinnedItems<Item: Identifiable>(
        kind: HomePinKind,
        source: [Item]
    ) -> [Item] where Item.ID == UUID {
        HomePinStore.orderedItems(
            ids: HomePinStore.orderedIDs(for: kind),
            source: source
        )
    }

    private func openFavorites() {
        model.requestNavigationDestination(.favorites)
    }
}
