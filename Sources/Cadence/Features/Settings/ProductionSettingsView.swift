import SwiftUI

enum SettingsLayoutMetrics {
    static let sectionSpacing = CadenceLayout.contentGap
    static let cardInset = CadenceLayout.contentGap
    static let cardContentSpacing = CadenceLayout.controlGap
    static let maximumContentWidth: CGFloat = 640
}

enum SettingsBooleanControlStyle: Equatable, Sendable {
    case nativeSwitch
}

enum SettingsBooleanControlPresentation {
    static let style = SettingsBooleanControlStyle.nativeSwitch
}

enum CadenceSettingsTab: String, CaseIterable, Identifiable {
    case general
    case library
    case sidebar
    case remote
    case shortcuts
    case updates
    case about

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .library: String(localized: "Library")
        case .sidebar: String(localized: "Sidebar")
        case .remote: String(localized: "Remote Media")
        case .shortcuts: String(localized: "Shortcuts")
        case .updates: String(localized: "Updates")
        case .about: String(localized: "About")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .library: "externaldrive"
        case .sidebar: "sidebar.left"
        case .remote: "network"
        case .shortcuts: "keyboard"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }
}

struct ProductionSettingsView: View {
    @Bindable var model: CadenceAppModel
    let tab: CadenceSettingsTab
    let updateController: CadenceUpdateController?
    let openDestination: ((NavigationDestination) -> Void)?
    @State private var defaultAudioApplication: DefaultAudioApplicationController
    @AppStorage("appearance")
    private var appearanceRawValue = CadenceAppearance.system.rawValue
    @AppStorage("navigationRail.order")
    private var navigationOrderRawValue =
        NavigationRailConfiguration.defaultOrderRawValue
    @AppStorage("navigationRail.hidden")
    private var hiddenNavigationRawValue = ""
    @AppStorage(CadenceModePreferences.isEnabledKey)
    private var isCadenceModeEnabled = CadenceModeOptions.default.isEnabled
    @AppStorage(CadenceModePreferences.reactsToBassKey)
    private var cadenceModeReactsToBass = CadenceModeOptions.default.reactsToBass
    @AppStorage(CadenceModePreferences.showsLyricsKey)
    private var cadenceModeShowsLyrics = CadenceModeOptions.default.showsLyrics
    @AppStorage(CadenceModePreferences.showsTrackInformationKey)
    private var cadenceModeShowsTrackInformation =
        CadenceModeOptions.default.showsTrackInformation
    @AppStorage(CadenceModePreferences.staysActiveKey)
    private var staysInCadenceMode = CadenceModeOptions.default.staysActive

    init(
        model: CadenceAppModel,
        tab: CadenceSettingsTab = .general,
        updateController: CadenceUpdateController? = nil,
        defaultAudioApplication: DefaultAudioApplicationController? = nil,
        openDestination: ((NavigationDestination) -> Void)? = nil
    ) {
        self.model = model
        self.tab = tab
        self.updateController = updateController
        self.openDestination = openDestination
        _defaultAudioApplication = State(
            initialValue: defaultAudioApplication
                ?? DefaultAudioApplicationController()
        )
    }

    var body: some View {
        CadencePageScrollView(
            maxContentWidth: SettingsLayoutMetrics.maximumContentWidth,
            sectionSpacing: SettingsLayoutMetrics.sectionSpacing
        ) {
            tabContent
        }
        .toggleStyle(.switch)
        .alert(
            "Couldn’t Move Library",
            isPresented: Binding(
                get: { model.libraryRelocationError != nil },
                set: {
                    if !$0 {
                        model.dismissLibraryRelocationError()
                    }
                }
            )
        ) {
            Button("Dismiss", role: .cancel) {
                model.dismissLibraryRelocationError()
            }
        } message: {
            Text(
                ProductErrorMessage(
                    detail: model.libraryRelocationError
                        ?? String(localized: "Cadence could not move the library."),
                    preservedState: String(localized: "The original library remains in place."),
                    recoveryAction: String(localized: "Choose another location and try again.")
                ).text
            )
        }
        .confirmationDialog(
            "Cadence Folder Already Exists",
            isPresented: Binding(
                get: { model.pendingLibraryConflictParent != nil },
                set: {
                    if !$0 {
                        model.libraryRelocationState.pendingConflictParent = nil
                    }
                }
            )
        ) {
            Button("Open Existing Library") {
                Task { await model.openConflictingLibrary() }
            }
            Button("Choose Another Folder") {
                model.chooseAnotherLibraryLocation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cadence will never merge with or overwrite an existing library folder.")
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .general:
            defaultAudioApplicationCard
            appearanceCard
            cadenceModeCard
        case .library:
            ManagedLibrarySettingsCard(
                model: model,
                openDestination: openDestination
            )
        case .sidebar:
            SettingsSidebarCard(
                orderRawValue: $navigationOrderRawValue,
                hiddenRawValue: $hiddenNavigationRawValue
            )
        case .remote:
            if let remoteLibraryController = model.remoteLibraryController {
                RemoteLibrarySettingsView(controller: remoteLibraryController)
            } else {
                ContentUnavailableView(
                    "Remote Media Unavailable",
                    systemImage: "network.slash",
                    description: Text(
                        "Remote media is not configured for this library."
                    )
                )
            }
        case .shortcuts:
            ShortcutsSettingsView()
        case .updates:
            if let updateController {
                UpdatesSettingsView(updateController: updateController)
            } else {
                ContentUnavailableView(
                    "Updates Unavailable",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text(
                        "Update controls are unavailable in this preview."
                    )
                )
            }
        case .about:
            SettingsAboutSection()
        }
    }

    private var appearanceCard: some View {
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
    }

    private var defaultAudioApplicationCard: some View {
        SettingsCard(
            title: "Audio Files",
            symbol: "play.rectangle"
        ) {
            HStack(spacing: CadenceLayout.controlGap) {
                VStack(alignment: .leading, spacing: CadenceLayout.textStack) {
                    Text(
                        defaultAudioApplication.isDefaultForAllSupportedAudio
                            ? "Cadence is the default audio player"
                            : "Open supported audio files with Cadence"
                    )
                    .font(.callout.weight(.medium))

                    Text(
                        "Opening a file plays it temporarily. Cadence adds it "
                            + "to the library only when you choose Add to Library."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: CadenceLayout.contentGap)

                Button(
                    defaultAudioApplication.isDefaultForAllSupportedAudio
                        ? "Default"
                        : "Use Cadence as Default"
                ) {
                    Task {
                        await defaultAudioApplication.setCadenceAsDefault()
                    }
                }
                .disabled(
                    defaultAudioApplication.isChanging
                        || defaultAudioApplication.isDefaultForAllSupportedAudio
                )
            }

            if defaultAudioApplication.isChanging {
                ProgressView("Updating file associations…")
                    .controlSize(.small)
            }

            if let errorMessage = defaultAudioApplication.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            defaultAudioApplication.refresh()
        }
    }

    private var cadenceModeCard: some View {
        SettingsCard(
            title: "Cadence Mode",
            symbol: "waveform"
        ) {
            Toggle("Enable Cadence Mode", isOn: $isCadenceModeEnabled)

            Toggle("React to Bass", isOn: $cadenceModeReactsToBass)
                .disabled(!isCadenceModeEnabled)

            Toggle(
                "Show Synchronized Lyrics",
                isOn: $cadenceModeShowsLyrics
            )
            .disabled(!isCadenceModeEnabled)

            Toggle(
                "Show Track Information",
                isOn: $cadenceModeShowsTrackInformation
            )
            .disabled(!isCadenceModeEnabled)

            Toggle("Stay in Cadence Mode", isOn: $staysInCadenceMode)
                .disabled(!isCadenceModeEnabled)

            Text(
                cadenceModeHelpText
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var cadenceModeHelpText: LocalizedStringKey {
        guard isCadenceModeEnabled else {
            return "The Z + X shortcut, visual effects, and direct entry are disabled."
        }
        return staysInCadenceMode
            ? "Cadence Mode stays open until you leave it."
            : "Cadence Mode closes after ten seconds without input."
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
}

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: SettingsLayoutMetrics.cardContentSpacing
        ) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .padding(SettingsLayoutMetrics.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CadenceTheme.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup))
        .overlay {
            RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup)
                .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
        }
    }
}
