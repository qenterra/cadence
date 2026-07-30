import SwiftUI

struct ProductionSettingsView: View {
    @Bindable var model: CadenceAppModel
    @AppStorage("appearance")
    private var appearanceRawValue = CadenceAppearance.system.rawValue
    @AppStorage("navigationRail.order")
    private var navigationOrderRawValue =
        NavigationRailConfiguration.defaultOrderRawValue
    @AppStorage("navigationRail.hidden")
    private var hiddenNavigationRawValue = ""

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

                    Text(
                        "Cadence keeps its monochrome accent and follows "
                            + "reduced-motion and accessibility preferences "
                            + "from macOS automatically."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                SettingsCard(
                    title: "Sidebar",
                    symbol: "sidebar.left"
                ) {
                    Text(
                        "Choose which destinations appear and drag their "
                            + "priority with the arrow controls."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(
                        Array(orderedNavigationDestinations.enumerated()),
                        id: \.element
                    ) { index, destination in
                        HStack(spacing: 12) {
                            Toggle(
                                isOn: navigationVisibilityBinding(
                                    for: destination
                                )
                            ) {
                                Label(
                                    destination.title,
                                    systemImage: destination.symbolName
                                )
                            }

                            Spacer(minLength: 8)

                            Button {
                                moveNavigationDestination(
                                    at: index,
                                    offset: -1
                                )
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .help("Move \(destination.title) Up")

                            Button {
                                moveNavigationDestination(
                                    at: index,
                                    offset: 1
                                )
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(
                                index == orderedNavigationDestinations.count - 1
                            )
                            .help("Move \(destination.title) Down")
                        }
                        .frame(minHeight: 30)
                    }
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

    private var orderedNavigationDestinations: [NavigationDestination] {
        NavigationRailConfiguration.orderedDestinations(
            from: navigationOrderRawValue
        )
    }

    private func navigationVisibilityBinding(
        for destination: NavigationDestination
    ) -> Binding<Bool> {
        Binding(
            get: {
                !NavigationRailConfiguration.hiddenDestinations(
                    from: hiddenNavigationRawValue
                ).contains(destination)
            },
            set: { isVisible in
                var hidden = NavigationRailConfiguration.hiddenDestinations(
                    from: hiddenNavigationRawValue
                )
                if isVisible {
                    hidden.remove(destination)
                } else {
                    hidden.insert(destination)
                }
                hiddenNavigationRawValue =
                    NavigationRailConfiguration.encode(hidden)
            }
        )
    }

    private func moveNavigationDestination(
        at index: Int,
        offset: Int
    ) {
        var destinations = orderedNavigationDestinations
        let targetIndex = index + offset
        guard
            destinations.indices.contains(index),
            destinations.indices.contains(targetIndex)
        else {
            return
        }
        destinations.swapAt(index, targetIndex)
        navigationOrderRawValue =
            NavigationRailConfiguration.encode(destinations)
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
