import SwiftUI

struct ArtistShelf: View {
    @Bindable var model: CadenceAppModel

    let kind: ArtistShelfKind
    let metrics: ArtistsLayoutMetrics

    var body: some View {
        let projection = model.artistShelfProjection(
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
                        model.requestShowAllArtists(kind)
                    }
                    .buttonStyle(.link)
                    .help("Show all \(kind.title.lowercased()) artists")
                }
            }

            if kind == .favorites, projection.artists.isEmpty {
                ArtistsEmptyState {
                    model.artistsOverviewScrollAnchor = .section(.allArtists)
                }
            } else {
                HStack(
                    alignment: .top,
                    spacing: ArtistsLayoutMetrics.tileSpacing
                ) {
                    ForEach(projection.artists) { artist in
                        ArtistTile(
                            model: model,
                            artist: artist,
                            width: metrics.tileWidth,
                            origin: .overview
                        )
                    }
                }
            }
        }
        .id(sectionAnchor)
    }

    private var sectionAnchor: ArtistBrowseAnchor {
        switch kind {
        case .recentlyPlayed:
            .section(.recentlyPlayed)
        case .favorites:
            .section(.favorites)
        }
    }
}

private struct ArtistsEmptyState: View {
    let browseAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.title3)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text("No favorite artists yet")
                    .font(.callout.weight(.semibold))
                Text("Favorite an artist to keep them close.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Browse Artists", action: browseAction)
        }
        .padding(.horizontal, 14)
        .frame(height: 66)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(CadenceTheme.subduedFill)
        )
        .accessibilityElement(children: .combine)
    }
}
