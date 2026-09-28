import SwiftUI

struct SettingsTrackListsCard: View {
    @AppStorage(CadencePreferences.Keys.trackTableDensity)
    private var densityRawValue = TrackTableDensity.standard.rawValue
    @AppStorage(CadencePreferences.Keys.showsTrackArtwork)
    private var showsTrackArtwork = true
    @AppStorage(CadencePreferences.Keys.collectionListWidthMode)
    private var listWidthModeRawValue = CollectionListWidthMode.shared.rawValue
    @AppStorage(CadencePreferences.Keys.collectionListWidth)
    private var sharedListWidth = 270.0
    @AppStorage(CadencePreferences.Keys.playlistListWidth)
    private var playlistListWidth = 270.0
    @AppStorage(CadencePreferences.Keys.smartCollectionListWidth)
    private var smartCollectionListWidth = 270.0
    @AppStorage(CadencePreferences.Keys.tagListWidth)
    private var tagListWidth = 300.0

    var body: some View {
        SettingsCard(title: "Track lists", symbol: "list.bullet.rectangle") {
            Picker("Row spacing", selection: densityBinding) {
                ForEach(TrackTableDensity.allCases) { density in
                    Text(density.title).tag(density)
                }
            }

            SettingsToggleRow(
                "Show artwork",
                isOn: $showsTrackArtwork
            )

            HStack(alignment: .center, spacing: CadenceLayout.contentGap) {
                VStack(alignment: .leading, spacing: CadenceLayout.textStack) {
                    Text("Share browser column widths")
                    Text("Use the same sidebar width for Playlists, Smart Collections, and Tags.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: CadenceLayout.contentGap)
                Toggle("", isOn: sharedListWidthsBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack {
                VStack(alignment: .leading, spacing: CadenceLayout.textStack) {
                    Text("Default layout")
                    Text("Restore columns, sorting, row spacing, and artwork in every track list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: CadenceLayout.contentGap)

                Button("Restore Defaults") {
                    TrackTablePreferences.reset()
                    densityRawValue = TrackTableDensity.standard.rawValue
                    showsTrackArtwork = true
                }
            }
        }
    }

    private var sharedListWidthsBinding: Binding<Bool> {
        Binding(
            get: { listWidthModeRawValue != CollectionListWidthMode.individual.rawValue },
            set: {
                if !$0 {
                    playlistListWidth = sharedListWidth
                    smartCollectionListWidth = sharedListWidth
                    tagListWidth = sharedListWidth
                }
                listWidthModeRawValue = $0
                    ? CollectionListWidthMode.shared.rawValue
                    : CollectionListWidthMode.individual.rawValue
            }
        )
    }

    private var densityBinding: Binding<TrackTableDensity> {
        Binding(
            get: {
                TrackTableDensity(rawValue: densityRawValue) ?? .standard
            },
            set: { densityRawValue = $0.rawValue }
        )
    }
}
