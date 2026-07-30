import SwiftUI

struct ArtistListeningHeader: View {
    @Bindable var model: CadenceAppModel

    let artist: ArtistPreview
    let totalWidth: CGFloat

    var body: some View {
        let artworkSize = ArtistDetailLayoutMetrics(
            totalWidth: totalWidth
        ).artworkSize

        HStack(alignment: .center, spacing: 34) {
            ArtistArtworkView(
                artist: artist,
                source: model.resolvedArtwork(for: artist)
            )
            .frame(width: artworkSize, height: artworkSize)
            .shadow(color: .black.opacity(0.24), radius: 14, y: 7)

            VStack(alignment: .leading, spacing: 0) {
                Text(artist.name)
                    .font(.system(size: 32, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(metadata)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 11)

                ArtistTagChips(model: model, artist: artist)
                    .padding(.top, 14)

                actions
                    .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
    }

    private var metadata: String {
        "\(artist.albumCount) "
            + "\(artist.albumCount == 1 ? "album" : "albums")  ·  "
            + "\(artist.trackCount) "
            + "\(artist.trackCount == 1 ? "track" : "tracks")"
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.playArtist(artist)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(model.tracksForArtist(artist.id).isEmpty)

            Button {
                model.shuffleArtist(artist)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(.bordered)
            .disabled(model.tracksForArtist(artist.id).isEmpty)

            Button {
                model.toggleFavorite(artist)
            } label: {
                Image(
                    systemName: model.isFavorite(artist)
                        ? "heart.fill"
                        : "heart"
                )
                .frame(width: 20)
            }
            .buttonStyle(.bordered)
            .help(
                model.isFavorite(artist)
                    ? "Remove from Favorites"
                    : "Add to Favorites"
            )
            .accessibilityLabel(
                model.isFavorite(artist)
                    ? "Remove artist from Favorites"
                    : "Add artist to Favorites"
            )
            .accessibilityValue(
                model.isFavorite(artist) ? "Favorite" : "Not favorite"
            )

            imageMenu
        }
        .controlSize(.large)
    }

    private var imageMenu: some View {
        Menu {
            ArtworkMenuItems(
                model: model,
                target: .artist(artist.id),
                label: "Artist Image"
            )
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 20)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .help("More Artist Actions")
    }
}
