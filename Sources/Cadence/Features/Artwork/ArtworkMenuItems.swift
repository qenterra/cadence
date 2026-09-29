import SwiftUI

struct ArtworkActionButtons: View {
    @Bindable var model: CadenceAppModel

    let target: ArtworkTarget
    let label: String

    var body: some View {
        HStack(spacing: CadenceLayout.controlGap) {
            Button(
                model.hasCustomArtwork(for: target)
                    ? "Replace \(label)"
                    : "Choose \(label)",
                systemImage: "photo"
            ) {
                model.requestArtworkImport(for: target)
            }
            .buttonStyle(.bordered)

            Button(
                "Remove \(label)",
                systemImage: "trash",
                role: .destructive
            ) {
                model.removeCustomArtwork(for: target)
            }
            .buttonStyle(.bordered)
            .disabled(!model.hasCustomArtwork(for: target))
        }
    }
}
