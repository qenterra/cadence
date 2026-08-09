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
                switch layout.kind {
                case .empty:
                    emptyArtwork
                case .single:
                    tile(at: 0)
                case .split:
                    HStack(spacing: 1) {
                        tile(at: 0)
                        tile(at: 1)
                    }
                case .trio:
                    HStack(spacing: 1) {
                        tile(at: 0)

                        VStack(spacing: 1) {
                            tile(at: 1)
                            tile(at: 2)
                        }
                    }
                case .grid:
                    VStack(spacing: 1) {
                        HStack(spacing: 1) {
                            tile(at: 0)
                            tile(at: 1)
                        }

                        HStack(spacing: 1) {
                            tile(at: 2)
                            tile(at: 3)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Artwork mosaic for \(title)")
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

    private var emptyArtwork: some View {
        ZStack {
            CadenceTheme.secondarySurface

            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(.tertiary)
        }
    }
}
