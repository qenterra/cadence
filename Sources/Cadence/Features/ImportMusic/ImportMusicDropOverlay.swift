import QenTerraComponents
import SwiftUI

struct ImportMusicDropOverlay: View {
    var body: some View {
        DropZone(
            state: .targeted(accessibilityValue: "Drop music to review"),
            title: "Drop to Review Music",
            message: "Cadence will scan a preview before anything is imported.",
            visualStyle: .cadenceOverlay
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Drop music to review. No files will be imported immediately."
        )
    }
}
