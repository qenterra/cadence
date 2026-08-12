import SwiftUI

struct ProductionArtworkView: View {
    @Bindable var model: CadenceAppModel
    let artworkID: UUID?
    let title: String
    let placeholder: ArtworkPlaceholder
    var variant: ArtworkAssetVariant = .thumbnail
    var cornerRadius: CGFloat = 8
    var showsBorder = true

    @State private var asset: ArtworkAsset?

    var body: some View {
        MediaArtworkView(
            source: asset.map(ResolvedArtworkSource.custom)
                ?? .placeholder(placeholder),
            title: title,
            placeholder: placeholder,
            cornerRadius: cornerRadius,
            showsBorder: showsBorder
        )
        .task(id: "\(artworkID?.uuidString ?? "none")-\(variant)") {
            guard let artworkID else {
                asset = nil
                return
            }
            asset = await model.playbackArtworkAsset(
                id: artworkID,
                variant: variant
            )
        }
    }
}
