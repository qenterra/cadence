import SwiftUI

enum SettingsLayoutMetrics {
    static let sectionSpacing = CadenceLayout.contentGap
    static let cardInset = CadenceLayout.contentGap
    static let cardContentSpacing = CadenceLayout.controlGap
    static let maximumContentWidth: CGFloat = 680
}

enum CadenceSettingsTab: String, CaseIterable, Identifiable {
    case general
    case playback
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
        case .playback: String(localized: "Playback")
        case .library: String(localized: "Library")
        case .sidebar: String(localized: "Navigation")
        case .remote: String(localized: "Remote Media")
        case .shortcuts: String(localized: "Shortcuts")
        case .updates: String(localized: "Updates")
        case .about: String(localized: "About")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .playback: "play.circle"
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
    let notificationController: CadenceNotificationController?
    let openDestination: ((NavigationDestination) -> Void)?
    @State private var defaultAudioApplication: DefaultAudioApplicationController
    @AppStorage("appearance")
    private var appearanceRawValue = CadenceAppearance.system.rawValue
    @AppStorage(CadencePreferences.Keys.catalogCardSize)
    private var catalogCardSizeRawValue = CatalogCardSize.automatic.rawValue
    @AppStorage(CadencePreferences.Keys.interfaceTextSize)
    private var interfaceTextSizeRawValue = InterfaceTextSize.standard.rawValue
    @AppStorage(CadencePreferences.Keys.startupPage)
    private var startupPageRawValue = StartupPage.home.rawValue
    @AppStorage("navigationRail.order")
    private var navigationOrderRawValue =
        NavigationRailConfiguration.defaultOrderRawValue
    @AppStorage("navigationRail.hidden")
    private var hiddenNavigationRawValue = ""
    @AppStorage(CadencePreferences.Keys.homeSectionOrder)
    private var homeSectionOrderRawValue =
        HomeSectionConfiguration.defaultOrderRawValue
    @AppStorage(CadencePreferences.Keys.hiddenHomeSections)
    private var hiddenHomeSectionsRawValue = ""

    init(
        model: CadenceAppModel,
        tab: CadenceSettingsTab = .general,
        updateController: CadenceUpdateController? = nil,
        notificationController: CadenceNotificationController? = nil,
        defaultAudioApplication: DefaultAudioApplicationController? = nil,
        openDestination: ((NavigationDestination) -> Void)? = nil
    ) {
        self.model = model
        self.tab = tab
        self.updateController = updateController
        self.notificationController = notificationController
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
            if let notificationController {
                NotificationsSettingsCard(
                    notificationController: notificationController
                )
            }
            SettingsDataCard {
                model.refreshPlaybackPreferences()
            }
        case .playback:
            SettingsPlaybackView(model: model)
        case .library:
            ManagedLibrarySettingsCard(
                model: model,
                openDestination: openDestination
            )
            SettingsTrackListsCard()
            SettingsLibraryRetentionCard(model: model)
        case .sidebar:
            SettingsHomeSectionsCard(
                orderRawValue: $homeSectionOrderRawValue,
                hiddenRawValue: $hiddenHomeSectionsRawValue
            )
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

            Picker("Card Size", selection: catalogCardSizeBinding) {
                ForEach(CatalogCardSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }

            Picker("Text Size", selection: interfaceTextSizeBinding) {
                ForEach(InterfaceTextSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }

            Picker("Page at Launch", selection: startupPageBinding) {
                ForEach(StartupPage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }

            Text(
                """
                Card size applies to albums, artists, playlists, smart collections, and Home. \
                Text size applies throughout the app. Track-list layout has its own Library settings.
                """
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
                .cadenceActionTint(.confirmation)
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
}

private extension ProductionSettingsView {
    var appearanceBinding: Binding<CadenceAppearance> {
        Binding(
            get: {
                CadenceAppearance(rawValue: appearanceRawValue) ?? .system
            },
            set: {
                appearanceRawValue = $0.rawValue
            }
        )
    }

    var catalogCardSizeBinding: Binding<CatalogCardSize> {
        Binding(
            get: {
                CatalogCardSize(rawValue: catalogCardSizeRawValue)
                    ?? .automatic
            },
            set: { catalogCardSizeRawValue = $0.rawValue }
        )
    }

    var interfaceTextSizeBinding: Binding<InterfaceTextSize> {
        Binding(
            get: {
                InterfaceTextSize(rawValue: interfaceTextSizeRawValue)
                    ?? .standard
            },
            set: { interfaceTextSizeRawValue = $0.rawValue }
        )
    }

    var startupPageBinding: Binding<StartupPage> {
        Binding(
            get: {
                StartupPage(rawValue: startupPageRawValue) ?? .home
            },
            set: { startupPageRawValue = $0.rawValue }
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
