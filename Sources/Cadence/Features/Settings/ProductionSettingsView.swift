import SwiftUI

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
        case .general: "General"
        case .library: "Library"
        case .sidebar: "Sidebar"
        case .remote: "Remote Media"
        case .shortcuts: "Shortcuts"
        case .updates: "Updates"
        case .about: "About"
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
    @AppStorage("appearance")
    private var appearanceRawValue = CadenceAppearance.system.rawValue
    @AppStorage("navigationRail.order")
    private var navigationOrderRawValue =
        NavigationRailConfiguration.defaultOrderRawValue
    @AppStorage("navigationRail.hidden")
    private var hiddenNavigationRawValue = ""

    init(
        model: CadenceAppModel,
        tab: CadenceSettingsTab = .general,
        updateController: CadenceUpdateController? = nil
    ) {
        self.model = model
        self.tab = tab
        self.updateController = updateController
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                tabContent
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CadenceTheme.contentBackground)
        .alert(
            "Library Move Failed",
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
                model.libraryRelocationError
                    ?? "Cadence could not move the library. The original library remains in place."
            )
        }
        .confirmationDialog(
            "Cadence.library Already Exists",
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
            Text("Cadence will never merge with or overwrite an existing library package.")
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .general:
            playbackCard
            appearanceCard
        case .library:
            ManagedLibrarySettingsCard(model: model)
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

    private var playbackCard: some View {
        SettingsCard(
            title: "Playback",
            symbol: "waveform"
        ) {
            Text(
                "Cadence uses its direct PCM path whenever the format and "
                    + "output allow it, with system playback for formats and "
                    + "routes that require native handling."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CadenceTheme.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusPanel))
        .overlay {
            RoundedRectangle(cornerRadius: CadenceTheme.radiusPanel)
                .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
        }
    }
}
