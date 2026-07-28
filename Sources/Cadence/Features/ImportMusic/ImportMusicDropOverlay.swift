import SwiftUI

struct ImportMusicDropOverlay: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 34, weight: .light))
                .accessibilityHidden(true)

            Text("Drop to Review Music")
                .font(.title3.weight(.semibold))

            Text("Cadence will scan a preview before anything is imported.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.opaqueSurface.opacity(0.97))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.34),
                    style: StrokeStyle(lineWidth: 2, dash: [9, 7])
                )
                .padding(18)
        }
        .padding(12)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Drop music to review. No files will be imported immediately."
        )
    }
}
