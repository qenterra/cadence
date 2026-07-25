import SwiftUI

struct AlbumTile: View {
    @Bindable var model: CadenceAppModel

    let album: AlbumPreview
    let width: CGFloat
    let origin: AlbumsBrowseOrigin

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            model.requestOpenAlbum(album, origin: origin)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ArtworkView(
                    palette: album.artworkPalette,
                    title: album.title,
                    cornerRadius: 7
                )
                .frame(width: width, height: width)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isFocused
                                ? Color.primary.opacity(0.72)
                                : Color.white.opacity(isHovered ? 0.22 : 0),
                            lineWidth: isFocused ? 1.5 : 1
                        )
                }

                Text(album.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.top, 8)

                Text(album.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(isHovered ? 0.94 : 1)
        }
        .buttonStyle(CadenceRowButtonStyle())
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .onChange(of: isFocused) { _, focused in
            if focused {
                model.updateAlbumsFocus(album.id)
            }
        }
        .accessibilityLabel("\(album.title), \(album.artist)")
        .accessibilityValue(
            model.isFavorite(album) ? "Favorite album" : "Album"
        )
    }
}

struct AlbumTileGrid: View {
    @Bindable var model: CadenceAppModel

    let albums: [AlbumPreview]
    let metrics: AlbumsLayoutMetrics
    let origin: AlbumsBrowseOrigin

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(
                    .fixed(metrics.tileWidth),
                    spacing: AlbumsLayoutMetrics.tileSpacing,
                    alignment: .top
                ),
                count: metrics.columnCount
            ),
            alignment: .leading,
            spacing: 24
        ) {
            ForEach(albums) { album in
                AlbumTile(
                    model: model,
                    album: album,
                    width: metrics.tileWidth,
                    origin: origin
                )
                .id(AlbumBrowseAnchor.album(album.id))
            }
        }
    }
}
