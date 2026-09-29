import QenTerraComponents
import SwiftUI

enum ImportMusicDropOverlayMetrics {
    static let minimumWidth = CGFloat(720)
    static let minimumHeight = CGFloat(480)
    static let inset = CGFloat(28)
}

struct ImportMusicDropOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.28))
                    .background(.ultraThinMaterial)
                    .accessibilityHidden(true)

                DropZone(
                    state: .targeted(accessibilityValue: "Drop music to review"),
                    title: "Drop to Review Music",
                    message: "Review files before adding them to your library.",
                    visualStyle: .cadenceOverlay
                )
                .frame(
                    width: max(geometry.size.width - ImportMusicDropOverlayMetrics.inset * 2, 0),
                    height: max(geometry.size.height - ImportMusicDropOverlayMetrics.inset * 2, 0)
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Drop music to review before importing."
        )
    }
}
