import SwiftUI

struct SettingsLibraryRetentionCard: View {
    @Bindable var model: CadenceAppModel

    @AppStorage(CadencePreferences.Keys.listeningHistoryRetention)
    private var listeningHistoryRetentionRawValue =
        ListeningHistoryRetention.forever.rawValue
    @AppStorage(CadencePreferences.Keys.trashCleanupRetention)
    private var trashCleanupRetentionRawValue = TrashCleanupRetention.never.rawValue

    var body: some View {
        SettingsCard(title: "Library maintenance", symbol: "clock.arrow.circlepath") {
            Picker("Keep listening history", selection: listeningHistoryRetentionBinding) {
                ForEach(ListeningHistoryRetention.allCases) { retention in
                    Text(retention.title).tag(retention)
                }
            }

            Picker("Empty Trash automatically", selection: trashCleanupRetentionBinding) {
                ForEach(TrashCleanupRetention.allCases) { retention in
                    Text(retention.title).tag(retention)
                }
            }

            Text(
                "Listening history never removes tracks. Items emptied from Trash are deleted permanently."
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
