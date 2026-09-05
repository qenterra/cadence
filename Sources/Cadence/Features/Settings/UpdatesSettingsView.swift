import SwiftUI

struct UpdatesSettingsView: View {
    let updateController: CadenceUpdateController

    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    @AppStorage(CadenceUpdateController.includesBetaUpdatesKey)
    private var includesBetaUpdates = false

    init(updateController: CadenceUpdateController) {
        self.updateController = updateController
        _automaticallyChecksForUpdates = State(
            initialValue: updateController.automaticallyChecksForUpdates
        )
        _automaticallyDownloadsUpdates = State(
            initialValue: updateController.automaticallyDownloadsUpdates
        )
    }

    var body: some View {
        SettingsCard(
            title: "Software Updates",
            symbol: "arrow.triangle.2.circlepath"
        ) {
            SettingsToggleRow(
                "Check for updates automatically",
                isOn: $automaticallyChecksForUpdates
            )
            .onChange(of: automaticallyChecksForUpdates) {
                updateController.automaticallyChecksForUpdates =
                    automaticallyChecksForUpdates
            }

            SettingsToggleRow(
                "Download and install updates automatically",
                isOn: $automaticallyDownloadsUpdates
            )
            .onChange(of: automaticallyDownloadsUpdates) {
                updateController.automaticallyDownloadsUpdates =
                    automaticallyDownloadsUpdates
            }
            .disabled(
                !automaticallyChecksForUpdates
                    || !updateController.allowsAutomaticUpdates
            )

            Divider()

            SettingsToggleRow(
                "Include beta updates",
                isOn: $includesBetaUpdates
            )
            .onChange(of: includesBetaUpdates) {
                updateController.updateChannelPreferenceDidChange()
            }

            Text(
                includesBetaUpdates
                    ? "Cadence will offer stable and beta releases. Beta builds may be less reliable."
                    : "Cadence will install stable releases only."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Check for Updates…") {
                    updateController.checkForUpdates()
                }
                .buttonStyle(.borderedProminent)
                .cadenceActionTint(.confirmation)

                Spacer()

                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
    }
}
