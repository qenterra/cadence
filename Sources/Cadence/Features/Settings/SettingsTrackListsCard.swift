import SwiftUI

struct SettingsTrackListsCard: View {
    @AppStorage(CadencePreferences.Keys.trackTableDensity)
    private var densityRawValue = TrackTableDensity.standard.rawValue
    @AppStorage(CadencePreferences.Keys.showsTrackArtwork)
    private var showsTrackArtwork = true

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

    private var densityBinding: Binding<TrackTableDensity> {
        Binding(
            get: {
                TrackTableDensity(rawValue: densityRawValue) ?? .standard
            },
            set: { densityRawValue = $0.rawValue }
        )
    }
}
