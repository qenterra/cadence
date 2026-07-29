import SwiftUI

struct ProductionSettingsView: View {
    @Bindable var model: CadenceAppModel
    @AppStorage("appearance")
    private var appearanceRawValue = CadenceAppearance.system.rawValue
    @AppStorage("accentPreset")
    private var accentRawValue = CadenceAccentPreset.monochrome.rawValue

    private var store: LibraryStore {
        model.librarySession.store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.largeTitle.bold())

                SettingsCard(
                    title: "Playback",
                    symbol: "waveform"
                ) {
                    Picker("Quality Profile", selection: qualityBinding) {
                        ForEach(AudioQualityProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(
                        "Spatialize Stereo in Immersive mode",
                        isOn: $model.isStereoSpatializationEnabled
                    )
                    .disabled(model.qualityProfile != .immersive)

                    Text(playbackDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsCard(
                    title: "Managed Library",
                    symbol: "externaldrive"
                ) {
                    LabeledContent("Location") {
                        Text(libraryPath)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Available Tracks") {
                        Text(store.catalogCounts.liveTrackCount.formatted())
                    }
                    LabeledContent("Tracks in Trash") {
                        Text(store.catalogCounts.trashedTrackCount.formatted())
                    }

                    HStack {
                        Button("Import Music…", systemImage: "folder.badge.plus") {
                            model.requestNavigationDestination(.importMusic)
                        }
                        Button("Open Trash", systemImage: "trash") {
                            model.requestNavigationDestination(.trash)
                        }
                    }
                }

                SettingsCard(
                    title: "Interface",
                    symbol: "circle.lefthalf.filled"
                ) {
                    Picker("Appearance", selection: appearanceBinding) {
                        ForEach(CadenceAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Accent") {
                        HStack(spacing: 10) {
                            ForEach(CadenceAccentPreset.allCases) { preset in
                                Button {
                                    accentRawValue = preset.rawValue
                                } label: {
                                    Circle()
                                        .fill(preset.color)
                                        .frame(width: 18, height: 18)
                                        .overlay {
                                            if accentPreset == preset {
                                                Circle()
                                                    .strokeBorder(
                                                        .primary,
                                                        lineWidth: 2
                                                    )
                                                    .padding(-4)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .help(preset.title)
                                .accessibilityLabel(preset.title)
                                .accessibilityValue(
                                    accentPreset == preset
                                        ? "Selected"
                                        : ""
                                )
                            }
                        }
                    }
                    Text(
                        "Cadence follows reduced-motion and accessibility "
                            + "preferences from macOS automatically."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CadenceTheme.contentBackground)
    }

    private var qualityBinding: Binding<AudioQualityProfile> {
        Binding(
            get: { model.qualityProfile },
            set: model.selectQualityProfile
        )
    }

    private var appearanceBinding: Binding<CadenceAppearance> {
        Binding(
            get: {
                CadenceAppearance(rawValue: appearanceRawValue) ?? .system
            },
            set: {
                appearanceRawValue = $0.rawValue
            }
        )
    }

    private var accentPreset: CadenceAccentPreset {
        CadenceAccentPreset(rawValue: accentRawValue) ?? .monochrome
    }

    private var libraryPath: String {
        model.librarySession.location?.packageURL.path
            ?? "~/Music/Cadence.library"
    }

    private var playbackDescription: String {
        switch model.qualityProfile {
        case .adaptive:
            "Chooses the safest high-quality path for the current file and output."
        case .pure:
            "Keeps stereo PCM playback direct whenever the format allows it."
        case .immersive:
            "Uses the system playback path for spatial and multichannel content."
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CadenceTheme.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
        }
    }
}
