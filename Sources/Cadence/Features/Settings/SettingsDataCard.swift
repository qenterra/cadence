import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsDataCard: View {
    let preferencesDidChange: () -> Void

    @State private var isResetConfirmationPresented = false
    @State private var notice: SettingsDataNotice?

    var body: some View {
        SettingsCard(title: "Settings backup", symbol: "externaldrive.badge.timemachine") {
            HStack {
                Button("Export…", systemImage: "square.and.arrow.up") {
                    exportSettings()
                }
                Button("Import…", systemImage: "square.and.arrow.down") {
                    importSettings()
                }

                Spacer(minLength: CadenceLayout.contentGap)

                Button(
                    "Reset Settings…",
                    systemImage: "arrow.counterclockwise",
                    role: .destructive
                ) {
                    isResetConfirmationPresented = true
                }
                .cadenceActionTint(.destructive)
            }

            Text(
                "Exports app preferences only. Your music, artwork, lyrics, Trash, and queue stay in Cadence."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            "Reset settings?",
            isPresented: $isResetConfirmationPresented
        ) {
            Button("Reset Settings", role: .destructive) {
                CadenceSettingsProfileService().resetCustomization()
                preferencesDidChange()
                notice = SettingsDataNotice(
                    title: String(localized: "Settings reset"),
                    message: String(
                        localized: "Default settings restored. Your library and queue were not changed."
                    )
                )
            }
            .cadenceActionTint(.destructive)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Your library, artwork, lyrics, Trash, and queue will not change."
            )
        }
        .alert(
            notice?.title ?? String(localized: "Settings"),
            isPresented: Binding(
                get: { notice != nil },
                set: {
                    if !$0 {
                        notice = nil
                    }
                }
            )
        ) {
            Button("Done", role: .cancel) { notice = nil }
        } message: {
            Text(notice?.message ?? "")
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Cadence Settings.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let data = try CadenceSettingsProfileService().exportData()
            try data.write(to: url, options: .atomic)
            notice = SettingsDataNotice(
                title: String(localized: "Settings exported"),
                message: url.path
            )
        } catch {
            showFailure(error)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            try CadenceSettingsProfileService().importData(data)
            preferencesDidChange()
            notice = SettingsDataNotice(
                title: String(localized: "Settings imported"),
                message: String(localized: "Imported settings are now in use.")
            )
        } catch {
            showFailure(error)
        }
    }

    private func showFailure(_ error: Error) {
        notice = SettingsDataNotice(
            title: String(localized: "Couldn’t update settings"),
            message: error.localizedDescription
        )
    }
}

private struct SettingsDataNotice {
    let title: String
    let message: String
}
