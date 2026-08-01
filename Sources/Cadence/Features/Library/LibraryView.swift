import SwiftUI

struct LibraryView: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        Group {
            if model.librarySession.availability != .preview {
                ProductionLibraryView(
                    model: model,
                    store: model.librarySession.store
                )
            } else if model.tracks.isEmpty {
                EmptyLibraryView(
                    title: "Your Library Is Empty",
                    description: "Import a folder to start building your Cadence library."
                ) {
                    model.requestNavigationDestination(.importMusic)
                }
            } else {
                GeometryReader { geometry in
                    let widths = LibraryColumnWidths(
                        totalWidth: geometry.size.width
                    )

                    HStack(spacing: 0) {
                        ArtistsColumn(model: model)
                            .frame(width: widths.artists)

                        LibraryColumnDivider()

                        AlbumsColumn(model: model)
                            .frame(width: widths.albums)

                        LibraryColumnDivider()

                        TracksColumn(model: model)
                            .frame(width: widths.tracks)
                    }
                }
            }
        }
        .background(CadenceTheme.contentBackground)
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: 76)
                .guideAnchor(.library)
                .allowsHitTesting(false)
        }
    }
}

struct LibraryColumnHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

private struct LibraryColumnDivider: View {
    var body: some View {
        Rectangle()
            .fill(CadenceTheme.separator)
            .frame(width: 1)
    }
}

struct LibraryColumnWidths {
    let artists: CGFloat
    let albums: CGFloat
    let tracks: CGFloat

    init(totalWidth: CGFloat) {
        let availableWidth = max(totalWidth - 2, 950)
        let proposedArtists = (availableWidth * 0.29).clamped(to: 260 ... 410)
        let proposedAlbums = (availableWidth * 0.32).clamped(to: 300 ... 460)
        let proposedTracks = availableWidth - proposedArtists - proposedAlbums

        if proposedTracks >= 390 {
            artists = proposedArtists
            albums = proposedAlbums
            tracks = proposedTracks
        } else {
            let deficit = 390 - proposedTracks
            let artistCapacity = proposedArtists - 260
            let albumCapacity = proposedAlbums - 300
            let totalCapacity = artistCapacity + albumCapacity
            let artistReduction = totalCapacity > 0
                ? deficit * (artistCapacity / totalCapacity)
                : 0
            let albumReduction = deficit - artistReduction

            artists = max(proposedArtists - artistReduction, 260)
            albums = max(proposedAlbums - albumReduction, 300)
            tracks = max(availableWidth - artists - albums, 390)
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
