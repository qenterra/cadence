import SwiftUI

struct ArtworkMenuItems: View {
    @Bindable var model: CadenceAppModel

    let target: ArtworkTarget
    let label: String

    var body: some View {
        Button(
            model.hasCustomArtwork(for: target)
                ? "Replace \(label)"
                : "Choose \(label)",
            systemImage: "photo"
        ) {
            model.requestArtworkImport(for: target)
        }

        if model.hasCustomArtwork(for: target) {
            Divider()

            Button(
                "Remove \(label)",
                systemImage: "trash",
                role: .destructive
            ) {
                model.removeCustomArtwork(for: target)
            }
        }
    }
}
