import SwiftUI

struct ArtistsOverview: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        GeometryReader { geometry in
            let metrics = ArtistsLayoutMetrics(totalWidth: geometry.size.width)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    overviewHeader

                    if !model.recentlyPlayedArtists.isEmpty {
                        ArtistShelf(
                            model: model,
                            kind: .recentlyPlayed,
                            metrics: metrics
                        )

                        sectionSeparator
                    }

                    ArtistShelf(
                        model: model,
                        kind: .favorites,
                        metrics: metrics
                    )

                    sectionSeparator

                    allArtistsSection(metrics: metrics)
                        .id(ArtistBrowseAnchor.section(.allArtists))
                }
                .padding(.horizontal, ArtistsLayoutMetrics.horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .scrollPosition(id: overviewScrollPosition)
        }
    }

    private var overviewHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Artists")
                    .font(.largeTitle.bold())

                Text(artistCountText(model.artists.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ArtistSortMenu(model: model)
        }
    }

    private var sectionSeparator: some View {
        Rectangle()
            .fill(CadenceTheme.separator)
            .frame(height: 1)
    }

    private func allArtistsSection(
        metrics: ArtistsLayoutMetrics
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("All Artists")
                .font(.title3.bold())

            ArtistTileGrid(
                model: model,
                artists: model.sortedAllArtists,
                metrics: metrics,
                origin: .overview
            )
        }
    }

    private var overviewScrollPosition: Binding<ArtistBrowseAnchor?> {
        Binding(
            get: { model.artistsOverviewScrollAnchor },
            set: { model.updateArtistsScrollAnchor($0, scope: nil) }
        )
    }

    private func artistCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "artist" : "artists")"
    }
}

struct ArtistSortMenu: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        Menu {
            ForEach(sortFields) { field in
                Button {
                    model.activateAllArtistsSort(field)
                } label: {
                    if model.allArtistsSortDescriptor.field == field {
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
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort All Artists")
    }

    private let sortFields: [ArtistSortField] = [
        .name,
        .recentlyPlayed,
        .albumCount,
        .trackCount,
    ]

    private var shortSortTitle: String {
        switch model.allArtistsSortDescriptor.field {
        case .name:
            "Name"
        case .recentlyPlayed:
            "Recent"
        case .albumCount:
            "Albums"
        case .trackCount:
            "Tracks"
        case .favoriteDate:
            "Favorite"
        }
    }

    private var directionSymbol: String {
        model.allArtistsSortDescriptor.direction == .ascending
            ? "chevron.up"
            : "chevron.down"
    }
}
