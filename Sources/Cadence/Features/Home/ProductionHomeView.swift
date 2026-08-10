import SwiftUI

struct ProductionHomeView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @AppStorage("home.pins.revision") private var pinRevision = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                CadencePageHeader(
                    "Home",
                    subtitle: "Your library, within reach"
                )

                if store.catalogCounts.liveTrackCount == 0 {
                    EmptyLibraryView(
                        title: "Make Cadence Your Home",
                        description: "Import music to build your listening space."
                    ) {
                        model.requestNavigationDestination(.importMusic)
                    }
                } else {
                    pinnedItems
                    recentlyPlayed
                    libraryShortcuts
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CadenceTheme.contentBackground)
    }

    private var recentlyPlayed: some View {
        HomeShelf(
            title: "Recently Played",
            subtitle: "Pick up where you left off"
        ) {
            let tracks = store.recentlyPlayedTracks
            if tracks.isEmpty {
                Text("Play a track and it will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HomeTrackGrid(
                    model: model,
                    tracks: tracks
                )
            }
        }
    }

    private var pinnedItems: some View {
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
                            symbol: "music.mic",
                            action: {
                                model.requestOpenProductionArtistContextually(
                                    id: artist.id
                                )
                            }
                        )
                    }
                    ForEach(playlists) { playlist in
                        HomePinnedDestinationTile(
                            title: playlist.name,
                            subtitle: "\(playlist.trackCount) tracks",
                            symbol: "music.note.list",
                            action: {
                                model.requestNavigationDestination(.playlists)
                                Task { await store.selectPlaylist(playlist.id) }
                            }
                        )
                    }
                    ForEach(smartCollections) { collection in
                        HomePinnedDestinationTile(
                            title: collection.name,
                            subtitle: "Smart Collection",
                            symbol: "slider.horizontal.3",
                            action: {
                                model.requestNavigationDestination(.smartCollections)
                                model.requestSelectSmartCollection(collection.id)
                            }
                        )
                    }
                }
            }
        }
    }

    private var pinnedAlbums: [LibraryAlbumProjection] {
        orderedPinnedItems(
            kind: .album,
            source: store.albums
        )
    }

    private var pinnedArtists: [LibraryArtistProjection] {
        orderedPinnedItems(
            kind: .artist,
            source: store.artists
        )
    }

    private var pinnedPlaylists: [LibraryPlaylistProjection] {
        orderedPinnedItems(
            kind: .playlist,
            source: store.playlists
        )
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

    private var libraryShortcuts: some View {
        HomeShelf(
            title: "Library",
            subtitle: "Browse without digging through the rail"
        ) {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 156), spacing: 12),
                ],
                alignment: .leading,
                spacing: 12
            ) {
                HomeDestinationTile(
                    destination: .albums,
                    subtitle: "\(store.albums.count) albums",
                    selection: $model.selectedDestination
                )
                HomeDestinationTile(
                    destination: .artists,
                    subtitle: "\(store.artists.count) artists",
                    selection: $model.selectedDestination
                )
                HomeDestinationTile(
                    destination: .playlists,
                    subtitle: "\(store.playlists.count) playlists",
                    selection: $model.selectedDestination
                )
                HomeDestinationTile(
                    destination: .smartCollections,
                    subtitle: "Your rules, ready to listen",
                    selection: $model.selectedDestination
                )
            }
        }
    }
}

private struct HomeShelf<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeTrackGrid: View {
    @Bindable var model: CadenceAppModel
    let tracks: [LibraryTrackProjection]

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16),
            ],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(tracks) { track in
                Button {
                    model.playProductionTrack(
                        track,
                        within: tracks,
                        source: .adHoc
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ProductionArtworkView(
                            model: model,
                            artworkID: track.artworkID,
                            title: track.title,
                            placeholder: .track,
                            cornerRadius: CadenceTheme.radiusGroup
                        )
                        .aspectRatio(1, contentMode: .fit)

                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(track.title) by \(track.artist)")
            }
        }
    }
}

private struct HomeDestinationTile: View {
    let destination: NavigationDestination
    let subtitle: String
    @Binding var selection: NavigationDestination

    var body: some View {
        Button {
            selection = destination
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: destination.symbolName)
                    .font(.title3)
                    .frame(width: 28)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(12)
            .background(CadenceTheme.subduedFill)
            .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup))
        }
        .buttonStyle(CadenceRowButtonStyle())
    }
}

private struct HomePinnedAlbumTile: View {
    @Bindable var model: CadenceAppModel
    let album: LibraryAlbumProjection

    var body: some View {
        Button {
            model.requestOpenProductionAlbumContextually(id: album.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ProductionArtworkView(
                    model: model,
                    artworkID: album.customArtworkID,
                    title: album.title,
                    placeholder: .album,
                    cornerRadius: CadenceTheme.radiusGroup
                )
                .aspectRatio(1, contentMode: .fit)
                Text(album.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HomePinnedDestinationTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: symbol)
                    .frame(width: 28)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(12)
            .background(CadenceTheme.subduedFill)
            .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup))
        }
        .buttonStyle(CadenceRowButtonStyle())
    }
}
