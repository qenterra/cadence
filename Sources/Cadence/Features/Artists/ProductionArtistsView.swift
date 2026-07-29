import SwiftUI

struct ProductionArtistsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore

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
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            header

                            LazyVGrid(
                                columns: columns(for: geometry.size.width),
                                alignment: .leading,
                                spacing: 28
                            ) {
                                ForEach(store.artists) { artist in
                                    artistTile(artist)
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                    }
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
        )
    }

    private func artistTile(
        _ artist: LibraryArtistProjection
    ) -> some View {
        ProductionArtistTile(
            model: model,
            store: store,
            artist: artist
        )
    }

    private func columns(
        for width: CGFloat
    ) -> [GridItem] {
        let contentWidth = max(width - 56, 600)
        let count = max(Int(contentWidth / 190), 3)
        return Array(
            repeating: GridItem(.flexible(), spacing: 18),
            count: count
        )
    }
}

private struct ProductionArtistTile: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let artist: LibraryArtistProjection
    @State private var isHovered = false

    var body: some View {
        Button {
            model.requestOpenProductionArtistContextually(id: artist.id)
        } label: {
            VStack(alignment: .center, spacing: 10) {
                ProductionArtworkView(
                    model: model,
                    artworkID: artist.customArtworkID,
                    title: artist.name,
                    placeholder: .artist,
                    cornerRadius: 0,
                    showsBorder: false
                )
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
                }

                Text(artist.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(
                    "\(artist.albumCount) albums · "
                        + "\(artist.trackCount) tracks"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(10)
            .background {
                BrowserRowSurface(
                    isSelected: false,
                    isHovered: isHovered,
                    isFocused: false
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CadenceRowButtonStyle())
        .onHover { isHovered = $0 }
        .contextMenu {
            artistActions
        }
        .task {
            if artist.id == store.artists.last?.id {
                await store.loadNextArtists()
            }
        }
    }

    @ViewBuilder
    private var artistActions: some View {
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
}
