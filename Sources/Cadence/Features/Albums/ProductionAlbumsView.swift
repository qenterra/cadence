import SwiftUI

struct ProductionAlbumsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore

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
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            header

                            LazyVGrid(
                                columns: columns(for: geometry.size.width),
                                alignment: .leading,
                                spacing: 24
                            ) {
                                ForEach(store.albums) { album in
                                    albumTile(album)
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
        )
    }

    private func albumTile(
        _ album: LibraryAlbumProjection
    ) -> some View {
        ProductionAlbumTile(
            model: model,
            store: store,
            album: album
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

private struct ProductionAlbumTile: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let album: LibraryAlbumProjection
    @State private var isHovered = false

    var body: some View {
        Button {
            model.requestOpenProductionAlbumContextually(id: album.id)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ProductionArtworkView(
                    model: model,
                    artworkID: album.customArtworkID,
                    title: album.title,
                    placeholder: .album,
                    cornerRadius: 10
                )
                .aspectRatio(1, contentMode: .fit)

                Text(album.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(album.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(albumDetail(album))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
            albumActions
        }
        .task {
            if album.id == store.albums.last?.id {
                await store.loadNextAlbums()
            }
        }
    }

    @ViewBuilder
    private var albumActions: some View {
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
