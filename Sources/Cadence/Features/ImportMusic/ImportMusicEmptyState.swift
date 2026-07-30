import SwiftUI

struct ImportMusicEmptyState: View {
    let isPreview: Bool
    let startScanning: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 28)

            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CadenceTheme.secondarySurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.2),
                        style: StrokeStyle(lineWidth: 1, dash: [7, 6])
                    )
            }

            VStack(spacing: 6) {
                Label(
                    "Original files stay untouched",
                    systemImage: "doc.on.doc"
                )
                .font(.callout.weight(.medium))

                Text(
                    isPreview
                        ? "A future import will copy supported audio into "
                        + "~/Music/Cadence.library after Review."
                        : "Cadence will copy included audio into "
                        + "~/Music/Cadence.library only after Review."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                if isPreview {
                    Text("This build only previews the workflow.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 540)

            Spacer(minLength: 28)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
