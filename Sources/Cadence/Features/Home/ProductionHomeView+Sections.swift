import SwiftUI

extension ProductionHomeView {
    @ViewBuilder
    var favorites: some View {
        let tracks = HomeListeningSelection.items(
            store.favoriteTracks,
            limit: 6
        )
        let albums = HomeListeningSelection.items(
            store.favoriteAlbums,
            limit: 6
        )
        let artists = HomeListeningSelection.items(
            store.favoriteArtists,
            limit: 6
        )

        if !tracks.isEmpty || !albums.isEmpty || !artists.isEmpty {
            HomeShelf(
                title: "Favorites",
                subtitle: "The music you keep coming back to",
                actionTitle: "See All",
                action: openFavorites
            ) {
                VStack(alignment: .leading, spacing: 22) {
                    if !tracks.isEmpty {
                        HomeSubsectionTitle("Songs")
                        HomeTrackGrid(
                            model: model,
                            tracks: tracks,
                            queueSource: .favorites
                        )
                    }

                    if !albums.isEmpty {
                        HomeSubsectionTitle("Albums")
                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(minimum: 150),
                                    spacing: 16
                                ),
                            ],
                            alignment: .leading,
                            spacing: 16
                        ) {
                            ForEach(albums) { album in
                                HomePinnedAlbumTile(model: model, album: album)
                            }
                        }
                    }

                    if !artists.isEmpty {
                        HomeSubsectionTitle("Artists")
                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(minimum: 190),
                                    spacing: 12
                                ),
                            ],
                            alignment: .leading,
                            spacing: 12
                        ) {
                            ForEach(artists) { artist in
                                HomePinnedDestinationTile(
                                    title: artist.name,
                                    subtitle: "Artist",
                                    symbol: "music.mic"
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

        if !albums.isEmpty {
            HomeShelf(title: HomePinKind.album.title, subtitle: "Kept close") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(albums) { album in
                        HomePinnedAlbumTile(model: model, album: album)
                    }
                }
            }
        }

        if !artists.isEmpty || !playlists.isEmpty || !smartCollections.isEmpty {
            HomeShelf(title: "Pinned", subtitle: "Your shortcuts") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(artists) { artist in
                        HomePinnedDestinationTile(
                            title: artist.name,
                            subtitle: "Artist",
                            symbol: "music.mic"
                        ) {
                            model.requestOpenProductionArtistContextually(
                                id: artist.id
                            )
                        }
                    }
                    ForEach(playlists) { playlist in
                        HomePinnedDestinationTile(
                            title: playlist.name,
                            subtitle: "\(playlist.trackCount) tracks",
                            symbol: "music.note.list"
                        ) {
                            model.requestNavigationDestination(.playlists)
                            Task { await store.selectPlaylist(playlist.id) }
                        }
                    }
                    ForEach(smartCollections) { collection in
                        HomePinnedDestinationTile(
                            title: collection.name,
                            subtitle: "Smart Collection",
                            symbol: "slider.horizontal.3"
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
        librarySectionRawValue = LibraryContentSection.favorites.rawValue
        model.requestNavigationDestination(.library)
    }
}
