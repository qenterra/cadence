import SwiftUI

struct ImportMusicEmptyState: View {
    let supportingText: LocalizedStringKey
    let footnote: LocalizedStringKey?
    let startScanning: () -> Void

    var body: some View {
        VStack(spacing: CadenceLayout.panelInset) {
            Spacer(minLength: CadenceLayout.pageInset)

            VStack(spacing: CadenceLayout.contentGap) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: CadenceLayout.compactGap) {
                    Text("Drop Music Here")
                        .font(.title3.weight(.semibold))

                    Text("Drop files or a folder anywhere in the workspace.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button("Choose Folder", action: startScanning)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .frame(maxWidth: 580, minHeight: 250)
            .background {
                RoundedRectangle(cornerRadius: CadenceTheme.radiusHero, style: .continuous)
                    .fill(CadenceTheme.secondarySurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: CadenceTheme.radiusHero, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.2),
                        style: StrokeStyle(lineWidth: 1, dash: [7, 6])
                    )
            }

            VStack(spacing: CadenceLayout.compactGap) {
                Label(
                    "Original files stay untouched",
                    systemImage: "doc.on.doc"
                )
                .font(.callout.weight(.medium))

                Text(supportingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 540)

            Spacer(minLength: CadenceLayout.pageInset)
        }
        .padding(CadenceLayout.sectionGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
