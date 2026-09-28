import SwiftUI

extension ProductionSearchResultsView {
    @ViewBuilder
    func artistActions(
        _ artist: LibraryArtistProjection
    ) -> some View {
        FavoriteContextMenuItem(isFavorite: artist.isFavorite) {
            Task {
                await model.setProductionArtistFavorite(
                    artist,
                    isFavorite: !artist.isFavorite
                )
            }
        }
        Divider()
        AddArtistToPlaylistMenuItems(
            store: store,
            artistID: artist.id
        )
        Divider()
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

    @ViewBuilder
    func albumActions(
        _ album: LibraryAlbumProjection
    ) -> some View {
        FavoriteContextMenuItem(isFavorite: album.isFavorite) {
            Task {
                await model.setProductionAlbumFavorite(
                    album,
                    isFavorite: !album.isFavorite
                )
            }
        }
        Divider()
        QuickAlbumTagMenuItems(
            store: store,
            albumID: album.id
        )
        AddAlbumToPlaylistMenuItems(
            store: store,
            albumID: album.id
        )
        Divider()
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

    func resultLabels(
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ProductionSearchMediaResult {
    let title: String
    let subtitle: String
    let artworkID: UUID?
    let placeholder: ArtworkPlaceholder
}
