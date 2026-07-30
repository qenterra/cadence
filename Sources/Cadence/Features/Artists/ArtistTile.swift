import SwiftUI

struct ArtistTile: View {
    @Bindable var model: CadenceAppModel

    let artist: ArtistPreview
    let width: CGFloat
    let origin: ArtistsBrowseOrigin

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            model.requestOpenArtist(artist, origin: origin)
        } label: {
            VStack(alignment: .center, spacing: 0) {
                ArtistArtworkView(
                    artist: artist,
                    source: model.resolvedArtwork(for: artist)
                )
                .frame(width: width, height: width)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isFocused
                                ? Color.primary.opacity(0.74)
                                : Color.white.opacity(isHovered ? 0.22 : 0),
                            lineWidth: isFocused ? 1.5 : 1
                        )
                }
                .shadow(
                    color: .black.opacity(isHovered ? 0.25 : 0.18),
                    radius: isHovered ? 12 : 8,
                    y: isHovered ? 6 : 4
                )

                Text(artist.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.top, 9)

                Text(albumCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .frame(width: width, alignment: .center)
            .contentShape(Rectangle())
            .opacity(isHovered ? 0.94 : 1)
        }
        .buttonStyle(CadenceRowButtonStyle())
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .onChange(of: isFocused) { _, focused in
            if focused {
                model.updateArtistsFocus(artist.id)
            }
        }
        .contextMenu {
            Button("Play", systemImage: "play.fill") {
                model.playArtist(artist)
            }
            Button(
                model.isFavorite(artist)
                    ? "Remove from Favorites"
                    : "Add to Favorites",
                systemImage: model.isFavorite(artist)
                    ? "heart.slash"
                    : "heart"
            ) {
                model.toggleFavorite(artist)
            }
        }
        .accessibilityLabel(artist.name)
        .accessibilityValue(accessibilityValue)
    }

    private var albumCountText: String {
        "\(artist.albumCount) \(artist.albumCount == 1 ? "album" : "albums")"
    }

    private var accessibilityValue: String {
        let favorite = model.isFavorite(artist) ? ", favorite" : ""
        return "\(albumCountText), \(artist.trackCount) tracks\(favorite)"
    }
}

struct ArtistTileGrid: View {
    @Bindable var model: CadenceAppModel

    let artists: [ArtistPreview]
    let metrics: ArtistsLayoutMetrics
    let origin: ArtistsBrowseOrigin

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(
                    .fixed(metrics.tileWidth),
                    spacing: ArtistsLayoutMetrics.tileSpacing,
                    alignment: .top
                ),
                count: metrics.columnCount
            ),
            alignment: .leading,
            spacing: 26
        ) {
            ForEach(artists) { artist in
                ArtistTile(
                    model: model,
                    artist: artist,
                    width: metrics.tileWidth,
                    origin: origin
                )
                .id(ArtistBrowseAnchor.artist(artist.id))
            }
        }
    }
}
