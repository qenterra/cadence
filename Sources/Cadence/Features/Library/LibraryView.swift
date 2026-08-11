import SwiftUI

struct LibraryView: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        ProductionLibraryView(
            model: model,
            store: model.librarySession.store
        )
        .background(CadenceTheme.contentBackground)
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: 76)
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

struct LibraryColumnWidths {
    let artists: CGFloat
    let albums: CGFloat
    let tracks: CGFloat

    init(totalWidth: CGFloat) {
        let availableWidth = max(totalWidth - 2, 0)
        if availableWidth < 950 {
            artists = (availableWidth * 0.27).clamped(to: 190 ... 260)
            albums = (availableWidth * 0.31).clamped(to: 230 ... 300)
            tracks = max(availableWidth - artists - albums, 0)
            return
        }
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
