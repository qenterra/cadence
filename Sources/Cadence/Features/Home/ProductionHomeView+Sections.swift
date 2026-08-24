import SwiftUI

extension ProductionHomeView {
    @ViewBuilder
    var favorites: some View {
        let recentTrackIDs = Set(
            HomeListeningSelection.recentItems(
                store.recentlyPlayedTracks,
                limit: 6
            ).map(\.id)
        )
        let excludedTrackIDs = recentTrackIDs.union(
            [model.currentPlaybackTrack?.id].compactMap(\.self)
        )
        let candidateTracks = HomeListeningSelection.items(
            store.favoriteTracks,
            excludingIDs: excludedTrackIDs,
            limit: store.favoriteTracks.count
        )
        let candidateAlbums = HomeListeningSelection.items(
            store.favoriteAlbums,
            excludingIDs: Set(pinnedAlbums.map(\.id)),
            limit: store.favoriteAlbums.count
        )
        let candidateArtists = HomeListeningSelection.items(
            store.favoriteArtists,
            excludingIDs: Set(pinnedArtists.map(\.id)),
            limit: store.favoriteArtists.count
        )
        let budget = HomeFavoritesPreviewBudget.resolve(
            trackCount: candidateTracks.count,
            albumCount: candidateAlbums.count,
            artistCount: candidateArtists.count,
            limit: 6
        )
        let tracks = HomeListeningSelection.items(
            candidateTracks,
            limit: budget.trackLimit
        )
        let albums = HomeListeningSelection.items(
            candidateAlbums,
            limit: budget.albumLimit
        )
        let artists = HomeListeningSelection.items(
            candidateArtists,
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
                        ProductionAlbumTile(
                            model: model,
                            store: store,
                            album: album
                        )
                    }

                    ForEach(artists) { artist in
                        ProductionArtistTile(
                            model: model,
                            store: store,
                            artist: artist
                        )
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
                        ProductionAlbumTile(
                            model: model,
                            store: store,
                            album: album
                        )
                    }
                    ForEach(artists) { artist in
                        ProductionArtistTile(
                            model: model,
                            store: store,
                            artist: artist
                        )
                    }
                    ForEach(playlists) { playlist in
                        HomeDestinationTile(
                            model: model,
                            title: playlist.name,
                            subtitle: "\(playlist.trackCount) tracks",
                            artworkID: playlist.customArtworkID,
                            placeholder: .playlist,
                            activationTarget: CatalogActivationTarget(
                                kind: .playlist,
                                id: playlist.id
                            )
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
                            placeholder: .smartCollection,
                            activationTarget: CatalogActivationTarget(
                                kind: .smartCollection,
                                id: collection.id
                            )
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
