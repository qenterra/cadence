import QenTerraMediaComponents
import SwiftUI

struct SmartCollectionArtworkMosaic: View {
    @Bindable var model: CadenceAppModel

    let layout: SmartCollectionArtworkLayout
    let title: String
    var artworkID: UUID?

    var body: some View {
        Group {
            if let artworkID {
                ProductionArtworkView(
                    model: model,
                    artworkID: artworkID,
                    title: title,
                    placeholder: .smartCollection,
                    variant: .original,
                    cornerRadius: CadenceTheme.radiusGroup
                )
            } else {
                ArtworkMosaic(
                    slotCount: layout.slots.count,
                    title: title,
                    cornerRadius: CadenceTheme.radiusGroup
                ) { index in
                    tile(at: index)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func tile(at index: Int) -> some View {
        if layout.slots.indices.contains(index) {
            let slot = layout.slots[index]
            MediaArtworkView(
                source: ArtworkResolver.album(
                    custom: model.customArtwork(
                        for: .album(slot.albumID)
                    ),
                    catalog: slot.palette
                ),
                title: slot.albumTitle,
                placeholder: .album,
                cornerRadius: CadenceTheme.radiusNone,
                showsBorder: false,
                fillsAvailableSpace: true
            )
        }
    }
}
