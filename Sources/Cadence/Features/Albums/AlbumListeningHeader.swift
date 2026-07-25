import SwiftUI

struct AlbumListeningHeader: View {
    @Bindable var model: CadenceAppModel

    let album: AlbumPreview

    var body: some View {
        GeometryReader { geometry in
            let artworkSize = AlbumDetailLayoutMetrics(
                totalWidth: geometry.size.width
            ).artworkSize

            HStack(alignment: .center, spacing: 34) {
                ArtworkView(
                    palette: album.artworkPalette,
                    title: album.title,
                    cornerRadius: 10
                )
                .frame(width: artworkSize, height: artworkSize)
                .shadow(color: .black.opacity(0.24), radius: 14, y: 7)

                VStack(alignment: .leading, spacing: 0) {
                    Text(album.title)
                        .font(.system(size: 30, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(album.artist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 6)

                    Text(metadata)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)

                    AlbumTagChips(model: model, album: album)
                        .padding(.top, 14)

                    actions
                        .padding(.top, 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 180, idealHeight: 220, maxHeight: 220)
    }

    private var metadata: String {
        "\(album.yearText)  ·  \(album.trackCount) "
            + "\(album.trackCount == 1 ? "track" : "tracks")  ·  "
            + album.durationText
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.playAlbum(album)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(model.selectedAlbumTracks.isEmpty)

            Button {
                model.shuffleAlbum(album)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedAlbumTracks.isEmpty)

            Button {
                model.toggleFavorite(album)
            } label: {
                Image(
                    systemName: model.isFavorite(album)
                        ? "heart.fill"
                        : "heart"
                )
                .frame(width: 20)
            }
            .buttonStyle(.bordered)
            .help(
                model.isFavorite(album)
                    ? "Remove from Favorites"
                    : "Add to Favorites"
            )
            .accessibilityLabel(
                model.isFavorite(album)
                    ? "Remove album from Favorites"
                    : "Add album to Favorites"
            )
            .accessibilityValue(
                model.isFavorite(album) ? "Favorite" : "Not favorite"
            )

            Menu {
                Button("Edit Album Tags", systemImage: "tag") {
                    model.openTagEditor(for: album)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.bordered)
            .help("More Album Actions")
        }
        .controlSize(.large)
    }
}
