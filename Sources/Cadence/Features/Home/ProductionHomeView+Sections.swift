import QenTerraComponents
import SwiftUI

extension ProductionHomeView {
    private var homeCatalogCardWidth: CGFloat {
        CatalogCardLayoutMetrics.preferredShelfWidth(
            for: CatalogCardSize(rawValue: homeCatalogCardSizeRawValue)
                ?? .automatic
        )
    }

    @ViewBuilder
    var tags: some View {
        if !store.tags.isEmpty {
            HomeShelf(title: String(localized: "Tags")) {
                DesignFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(store.tags) { tag in
                        CadenceTagPill(title: tag.displayPath) {
                            model.requestOpenProductionTagContextually(id: tag.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    var favorites: some View {
        let candidateTracks = HomeListeningSelection.favoriteItems(
            HomeFavoriteRecencyStore.orderedTracks(store.favoriteTracks),
            limit: store.favoriteTracks.count
        )
        let candidateAlbums = HomeListeningSelection.items(
            store.favoriteAlbums.sorted {
                ($0.favoriteDate ?? .distantPast) > ($1.favoriteDate ?? .distantPast)
            },
            excludingIDs: Set(pinnedAlbums.map(\.id)),
            limit: store.favoriteAlbums.count
        )
        let candidateArtists = HomeListeningSelection.items(
            store.favoriteArtists.sorted {
                ($0.favoriteDate ?? .distantPast) > ($1.favoriteDate ?? .distantPast)
            },
            excludingIDs: Set(pinnedArtists.map(\.id)),
            limit: store.favoriteArtists.count
        )
        let tracks = HomeListeningSelection.items(
            candidateTracks,
            limit: 5
        )
        let albums = HomeListeningSelection.items(
            candidateAlbums,
            limit: 10
        )
        let artists = HomeListeningSelection.items(
            candidateArtists,
            limit: 10
        )

        if !tracks.isEmpty {
            favoriteTracksShelf(tracks)
        }
        if !albums.isEmpty {
            favoriteAlbumsShelf(albums)
        }
        if !artists.isEmpty {
            favoriteArtistsShelf(artists)
        }
    }

    private func favoriteTracksShelf(_ tracks: [LibraryTrackProjection]) -> some View {
        HomeShelf(title: String(localized: "Favorite Tracks"), actionTitle: "See All", action: {
            openFavorites(.songs)
        }, content: {
            ProductionTrackList(
                model: model,
                tracks: tracks,
                contentVersion: store.favoriteTracksVersion,
                showsHeader: false,
                compact: true,
                queueSource: .favorites,
                scrollOwnership: .page
            )
        })
    }

    private func favoriteAlbumsShelf(_ albums: [LibraryAlbumProjection]) -> some View {
        HomeShelf(title: String(localized: "Favorite Albums"), actionTitle: "See All", action: {
            openFavorites(.albums)
        }, content: {
            HomeHorizontalShelf {
                ForEach(albums) { album in
                    ProductionAlbumTile(
                        model: model, store: store, album: album,
                        orderedTargets: albums.map { CatalogActivationTarget(kind: .album, id: $0.id) }
                    )
                    .frame(width: homeCatalogCardWidth)
                }
            }
        })
    }

    private func favoriteArtistsShelf(_ artists: [LibraryArtistProjection]) -> some View {
        HomeShelf(title: String(localized: "Favorite Artists"), actionTitle: "See All", action: {
            openFavorites(.artists)
        }, content: {
            HomeHorizontalShelf {
                ForEach(artists) { artist in
                    ProductionArtistTile(
                        model: model, store: store, artist: artist,
                        orderedTargets: artists.map { CatalogActivationTarget(kind: .artist, id: $0.id) }
                    )
                    .frame(width: homeCatalogCardWidth)
                }
            }
        })
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

        if !albums.isEmpty {
            HomeShelf(title: HomePinnedSectionKind.albums.title) {
                HomeCompactGrid {
                    ForEach(albums) { album in
                        ProductionAlbumTile(
                            model: model,
                            store: store,
                            album: album,
                            orderedTargets: albums.map {
                                CatalogActivationTarget(
                                    kind: .album,
                                    id: $0.id
                                )
                            }
                        )
                    }
                }
            }
        }

        if !artists.isEmpty {
            HomeShelf(title: HomePinnedSectionKind.artists.title) {
                HomeCompactGrid {
                    ForEach(artists) { artist in
                        ProductionArtistTile(
                            model: model,
                            store: store,
                            artist: artist,
                            orderedTargets: artists.map {
                                CatalogActivationTarget(
                                    kind: .artist,
                                    id: $0.id
                                )
                            }
                        )
                    }
                }
            }
        }

        if !playlists.isEmpty {
            HomeShelf(title: HomePinnedSectionKind.playlists.title) {
                HomeCompactGrid {
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

    var hasPinnedItems: Bool {
        !pinnedAlbums.isEmpty
            || !pinnedArtists.isEmpty
            || !pinnedPlaylists.isEmpty
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

    private func openFavorites(_ section: FavoriteCatalogSection) {
        UserDefaults.standard.set(section.rawValue, forKey: "library.favoriteSection")
        model.requestNavigationDestination(.favorites)
    }
}
