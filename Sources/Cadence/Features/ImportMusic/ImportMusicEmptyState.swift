import QenTerraComponents
import SwiftUI

struct ImportMusicEmptyState: View {
    let supportingText: LocalizedStringKey
    let footnote: LocalizedStringKey?
    let startScanning: () -> Void

    var body: some View {
        VStack(spacing: CadenceLayout.panelInset) {
            Spacer(minLength: CadenceLayout.pageInset)

            DropZone(
                state: .ready(accessibilityValue: "Ready for music"),
                title: "Drop Music Here",
                message: "Drop files or a folder anywhere in the workspace.",
                action: DropZoneAction(
                    title: "Choose Folder",
                    handler: startScanning
                ),
                visualStyle: .cadenceHero
            )

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
