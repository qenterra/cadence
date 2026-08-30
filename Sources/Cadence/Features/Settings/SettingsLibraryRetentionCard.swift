import SwiftUI

struct SettingsLibraryRetentionCard: View {
    @Bindable var model: CadenceAppModel

    @AppStorage(CadencePreferences.Keys.listeningHistoryRetention)
    private var listeningHistoryRetentionRawValue =
        ListeningHistoryRetention.forever.rawValue
    @AppStorage(CadencePreferences.Keys.trashCleanupRetention)
    private var trashCleanupRetentionRawValue = TrashCleanupRetention.never.rawValue

    var body: some View {
        SettingsCard(title: "History and Trash", symbol: "clock.arrow.circlepath") {
            Picker("Keep Listening History", selection: listeningHistoryRetentionBinding) {
                ForEach(ListeningHistoryRetention.allCases) { retention in
                    Text(retention.title).tag(retention)
                }
            }

            Picker("Empty Trash Automatically", selection: trashCleanupRetentionBinding) {
                ForEach(TrashCleanupRetention.allCases) { retention in
                    Text(retention.title).tag(retention)
                }
            }

            Text(
                """
                Shorter history periods clear old play dates without deleting tracks. \
                Automatic Trash cleanup permanently removes expired items from the managed library.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: listeningHistoryRetentionRawValue) {
            Task { await model.runConfiguredLibraryMaintenance() }
        }
        .onChange(of: trashCleanupRetentionRawValue) {
            Task { await model.runConfiguredLibraryMaintenance() }
        }
    }

    private var listeningHistoryRetentionBinding: Binding<ListeningHistoryRetention> {
        Binding(
            get: {
                ListeningHistoryRetention(
                    rawValue: listeningHistoryRetentionRawValue
                ) ?? .forever
            },
            set: { listeningHistoryRetentionRawValue = $0.rawValue }
        )
    }

    private var trashCleanupRetentionBinding: Binding<TrashCleanupRetention> {
        Binding(
            get: {
                TrashCleanupRetention(rawValue: trashCleanupRetentionRawValue)
                    ?? .never
            },
            set: { trashCleanupRetentionRawValue = $0.rawValue }
        )
    }
}
