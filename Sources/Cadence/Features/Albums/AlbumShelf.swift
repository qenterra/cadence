import SwiftUI

struct AlbumShelf: View {
    @Bindable var model: CadenceAppModel

    let kind: AlbumShelfKind
    let metrics: AlbumsLayoutMetrics

    var body: some View {
        let projection = model.albumShelfProjection(
            kind: kind,
            capacity: metrics.shelfCapacity
        )

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(kind.title)
                    .font(.title3.bold())

                Spacer()

                if projection.hasOverflow {
                    Button("See All") {
                        model.requestShowAll(kind)
                    }
                    .buttonStyle(.link)
                    .help("Show all \(kind.title.lowercased()) albums")
                }
            }

            if kind == .favorites, projection.albums.isEmpty {
                AlbumsEmptyState {
                    model.albumsOverviewScrollAnchor = .section(.allAlbums)
                }
            } else {
                HStack(alignment: .top, spacing: AlbumsLayoutMetrics.tileSpacing) {
                    ForEach(projection.albums) { album in
                        AlbumTile(
                            model: model,
                            album: album,
                            width: metrics.tileWidth,
                            origin: .overview
                        )
                    }
                }
            }
        }
        .id(sectionAnchor)
    }

    private var sectionAnchor: AlbumBrowseAnchor {
        switch kind {
        case .recentlyAdded:
            .section(.recentlyAdded)
        case .favorites:
            .section(.favorites)
        }
    }
}
