import QenTerraComponents
import SwiftUI

struct ImportMusicDropOverlay: View {
    var body: some View {
        DropZone(
            state: .targeted(accessibilityValue: "Drop music to review"),
            title: "Drop to Review Music",
            message: "Review files before adding them to your library.",
            visualStyle: .cadenceOverlay
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Drop music to review before importing."
        )
    }
}
