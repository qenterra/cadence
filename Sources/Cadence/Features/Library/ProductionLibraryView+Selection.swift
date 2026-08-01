import Foundation
import SwiftUI

extension ProductionLibraryView {
    func repairArtistSelection() {
        guard !store.artists.isEmpty else {
            selectedArtistID = nil
            selectedAlbumID = nil
            selectedTrackID = nil
            return
        }

        if !store.artists.contains(where: { $0.id == selectedArtistID }) {
            selectedArtistID = store.artists.first?.id
        }
    }

    func repairAlbumSelection() {
        if !visibleAlbums.contains(where: { $0.id == selectedAlbumID }) {
            selectedAlbumID = visibleAlbums.first?.id
        }
    }

    func repairTrackSelection() {
        if !visibleTracks.contains(where: { $0.id == selectedTrackID }) {
            selectedTrackID = visibleTracks.first?.id
        }
    }

    func projectionArtwork(
        artworkID: UUID?,
        title: String,
        placeholder: ArtworkPlaceholder,
        isCircular: Bool = false
    ) -> some View {
        ProductionArtworkView(
            model: model,
            artworkID: artworkID,
            title: title,
            placeholder: placeholder,
            cornerRadius: isCircular ? 0 : 7,
            showsBorder: !isCircular
        )
        .clipShape(
            isCircular
                ? AnyShape(Circle())
                : AnyShape(Rectangle())
        )
    }
}
