import SwiftUI

struct AlbumsOverview: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        GeometryReader { geometry in
            let metrics = AlbumsLayoutMetrics(totalWidth: geometry.size.width)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    overviewHeader
                        .id(AlbumBrowseAnchor.section(.recentlyAdded))

                    AlbumShelf(
                        model: model,
                        kind: .recentlyAdded,
                        metrics: metrics
                    )

                    sectionSeparator

                    AlbumShelf(
                        model: model,
                        kind: .favorites,
                        metrics: metrics
                    )

                    sectionSeparator

                    allAlbumsSection(metrics: metrics)
                        .id(AlbumBrowseAnchor.section(.allAlbums))
                }
                .padding(.horizontal, AlbumsLayoutMetrics.horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .scrollPosition(id: overviewScrollPosition)
        }
    }

    private var overviewHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Albums")
                    .font(.largeTitle.bold())

                Text("\(model.albums.count) albums")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            AlbumSortMenu(model: model)
        }
    }

    private var sectionSeparator: some View {
        Rectangle()
            .fill(CadenceTheme.separator)
            .frame(height: 1)
    }

    private func allAlbumsSection(
        metrics: AlbumsLayoutMetrics
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("All Albums")
                .font(.title3.bold())

            AlbumTileGrid(
                model: model,
                albums: model.sortedAllAlbums,
                metrics: metrics,
                origin: .overview
            )
        }
    }

    private var overviewScrollPosition: Binding<AlbumBrowseAnchor?> {
        Binding(
            get: { model.albumsOverviewScrollAnchor },
            set: { model.updateAlbumsScrollAnchor($0, scope: nil) }
        )
    }
}

struct AlbumSortMenu: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        Menu {
            ForEach(sortFields) { field in
                Button {
                    model.activateAllAlbumsSort(field)
                } label: {
                    if model.allAlbumsSortDescriptor.field == field {
                        Label(
                            field.title,
                            systemImage: directionSymbol
                        )
                    } else {
                        Text(field.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text("Sort by \(shortSortTitle)")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort All Albums")
    }

    private let sortFields: [AlbumSortField] = [
        .artist,
        .title,
        .dateAdded,
        .releaseYear,
    ]

    private var shortSortTitle: String {
        switch model.allAlbumsSortDescriptor.field {
        case .artist:
            "Artist"
        case .title:
            "Title"
        case .dateAdded:
            "Recent"
        case .releaseYear:
            "Year"
        case .favoriteDate:
            "Favorite"
        }
    }

    private var directionSymbol: String {
        model.allAlbumsSortDescriptor.direction == .ascending
            ? "chevron.up"
            : "chevron.down"
    }
}
