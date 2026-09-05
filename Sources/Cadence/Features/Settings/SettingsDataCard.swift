import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsDataCard: View {
    let preferencesDidChange: () -> Void

    @State private var isResetConfirmationPresented = false
    @State private var notice: SettingsDataNotice?

    var body: some View {
        SettingsCard(title: "Settings Data", symbol: "slider.horizontal.3") {
            HStack {
                Button("Export Settings…", systemImage: "square.and.arrow.up") {
                    exportSettings()
                }
                Button("Import Settings…", systemImage: "square.and.arrow.down") {
                    importSettings()
                }

                Spacer(minLength: CadenceLayout.contentGap)

                Button(
                    "Reset All Settings…",
                    systemImage: "arrow.counterclockwise",
                    role: .destructive
                ) {
                    isResetConfirmationPresented = true
                }
                .cadenceActionTint(.destructive)
            }

            Text(
                """
                Export includes interface and playback customization, but never the \
                library, remote credentials, cache, or saved queue.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            "Reset All Settings?",
            isPresented: $isResetConfirmationPresented
        ) {
            Button("Reset Settings", role: .destructive) {
                CadenceSettingsProfileService().resetCustomization()
                preferencesDidChange()
                notice = SettingsDataNotice(
                    title: String(localized: "Settings Reset"),
                    message: String(
                        localized: """
                        Cadence restored its default settings. Your library, remote \
                        connection, cache, and saved queue were not changed.
                        """
                    )
                )
            }
            .cadenceActionTint(.destructive)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This resets customization only. Your music library and its files remain untouched."
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
            Button("OK", role: .cancel) { notice = nil }
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
                title: String(localized: "Settings Exported"),
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
                title: String(localized: "Settings Imported"),
                message: String(localized: "Cadence applied the imported customization.")
            )
        } catch {
            showFailure(error)
        }
    }

    private func showFailure(_ error: Error) {
        notice = SettingsDataNotice(
            title: String(localized: "Settings Couldn’t Be Changed"),
            message: error.localizedDescription
        )
    }
}

private struct SettingsDataNotice {
    let title: String
    let message: String
}
