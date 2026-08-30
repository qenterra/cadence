import SwiftUI

struct SettingsTrackListsCard: View {
    @AppStorage(CadencePreferences.Keys.trackTableDensity)
    private var densityRawValue = TrackTableDensity.standard.rawValue
    @AppStorage(CadencePreferences.Keys.showsTrackArtwork)
    private var showsTrackArtwork = true

    var body: some View {
        SettingsCard(title: "Track Lists", symbol: "list.bullet.rectangle") {
            Picker("Row Density", selection: densityBinding) {
                ForEach(TrackTableDensity.allCases) { density in
                    Text(density.title).tag(density)
                }
            }

            SettingsToggleRow(
                "Show Artwork",
                isOn: $showsTrackArtwork
            )

            HStack {
                VStack(alignment: .leading, spacing: CadenceLayout.textStack) {
                    Text("Table Layout")
                    Text("Restores the default columns, sorting, density, and artwork layout in every track list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: CadenceLayout.contentGap)

                Button("Reset Track Lists") {
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
