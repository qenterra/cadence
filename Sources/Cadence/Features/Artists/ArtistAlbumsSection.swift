import SwiftUI

struct ArtistAlbumsSection: View {
    @Bindable var model: CadenceAppModel

    let artist: ArtistPreview
    let totalWidth: CGFloat

    var body: some View {
        let albums = sortedAlbums
        let metrics = AlbumsLayoutMetrics(totalWidth: totalWidth)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Albums")
                    .font(.title3.bold())

                Text(albums.count.formatted())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if albums.isEmpty {
                Text("No albums are available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                AlbumTileGrid(
                    model: model,
                    albums: albums,
                    metrics: metrics,
                    origin: .artist(artist.id)
                )
            }
        }
    }

    private var sortedAlbums: [AlbumPreview] {
        model.albumsForArtist(artist.id).sorted { lhs, rhs in
            if lhs.year != rhs.year {
                return lhs.year > rhs.year
            }
            return lhs.title.localizedStandardCompare(rhs.title)
                == .orderedAscending
        }
    }
}
