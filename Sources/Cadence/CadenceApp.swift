import AppKit
import SwiftUI

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(CadenceApplicationDelegate.self)
    private var applicationDelegate
    @State private var model = Self.makeInitialModel()
    @State private var appearanceController = AppearanceController()
    @State private var updateController = CadenceUpdateController(
        startsUpdater: !CadenceLaunchEnvironment.shouldUsePreviewLibrary()
    )
    @AppStorage("appearance")
    private var appearanceRawValue = CadenceAppearance.system.rawValue

    var body: some Scene {
        WindowGroup("Cadence") {
            CadenceRootView(model: model)
                .frame(
                    minWidth: AdaptiveLayoutPolicy.minimumWindowSize.width,
                    minHeight: AdaptiveLayoutPolicy.minimumWindowSize.height
                )
                .preferredColorScheme(appearance.colorScheme)
                .tint(CadenceTheme.primaryAccent)
                .onChange(
                    of: appearanceRawValue,
                    initial: true
                ) { _, _ in
                    appearanceController.apply(appearance)
                }
                .task {
                    applicationDelegate.connect { urls in
                        Task { @MainActor in
                            await model.openExternalAudio(urls: urls)
                        }
                    }
                    applicationDelegate.onTermination {
                        model.shutdownPlayback()
                    }
                }
        }
        .defaultSize(width: 1512, height: 982)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))

        Settings {
            CadenceSettingsWindow(
                model: model,
                updateController: updateController
            )
            .preferredColorScheme(appearance.colorScheme)
            .tint(CadenceTheme.primaryAccent)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateController.checkForUpdates()
                }
            }

            CommandMenu("Playback") {
                Button("Play or Pause") {
                    AppCommandRouter(model: model).handle(
                        .togglePlayback,
                        focus: .none
                    )
                }

                Divider()

                Button("Previous Track") {
                    AppCommandRouter(model: model).handle(
                        .previousTrack,
                        focus: .none
                    )
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Next Track") {
                    AppCommandRouter(model: model).handle(
                        .nextTrack,
                        focus: .none
                    )
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Divider()

                Button("Volume Up") {
                    AppCommandRouter(model: model).handle(
                        .volumeUp,
                        focus: .none
                    )
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button("Volume Down") {
                    AppCommandRouter(model: model).handle(
                        .volumeDown,
                        focus: .none
                    )
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
            }

            CommandMenu("Import") {
                Button("Choose Folder") {
                    model.chooseImportFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.selectedDestination != .importMusic)

                Divider()

                Button("Select All in Review") {
                    model.selectAllImportCandidates()
                }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(
                    model.selectedDestination != .importMusic
                        || model.importPreviewStage != .review
                )
            }

            CommandMenu("Tags") {
                Button("Edit Tags") {
                    model.toggleTagInspector()
                }
                .keyboardShortcut("t", modifiers: [.option, .command])
                .disabled(
                    model.selectedDestination != .tags
                        || model.tagEditingSelection.isEmpty
                )

                Divider()

                Button("Select All \(model.tagResultScope.title)") {
                    model.selectAllTagResults()
                }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(
                    model.selectedDestination != .tags
                        || !model.canSelectAllTagResults
                )
            }

            CommandMenu("Smart Collections") {
                Button("New Smart Collection") {
                    model.requestNavigationDestination(.smartCollections)
                    model.requestNewSmartCollection()
                }
                .keyboardShortcut("n", modifiers: [.option, .command])

                Divider()

                Button("Edit Rules") {
                    model.requestEditSelectedSmartCollection()
                }
                .disabled(
                    model.selectedDestination != .smartCollections
                        || model.smartCollectionsPresentationMode != .listening
                        || model.selectedSmartCollection == nil
                )

                Button("Done Editing") {
                    model.requestFinishSmartCollectionEditing()
                }
                .disabled(
                    model.selectedDestination != .smartCollections
                        || model.smartCollectionsPresentationMode != .editing
                )

                Divider()

                Button("Save Smart Collection") {
                    Task {
                        await model.saveSmartCollectionDraftPersisting()
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(
                    model.selectedDestination != .smartCollections
                        || model.smartCollectionsPresentationMode != .editing
                        || !model.canSaveSmartCollectionDraft
                )

                Button("Revert Smart Collection") {
                    model.revertSmartCollectionDraft()
                }
                .disabled(
                    model.selectedDestination != .smartCollections
                        || model.smartCollectionsPresentationMode != .editing
                        || !model.canRevertSmartCollectionDraft
                )
            }
        }
    }

    private var appearance: CadenceAppearance {
        CadenceAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private static func makeInitialModel() -> CadenceAppModel {
        if CadenceLaunchEnvironment.shouldUsePreviewLibrary() {
            return .preview()
        }
        return .production(librarySession: .startup())
    }
}

struct CadenceSettingsWindow: View {
    @Bindable var model: CadenceAppModel
    let updateController: CadenceUpdateController
    @State private var selection: CadenceSettingsTab

    init(
        model: CadenceAppModel,
        updateController: CadenceUpdateController,
        selection: CadenceSettingsTab = .general
    ) {
        self.model = model
        self.updateController = updateController
        _selection = State(initialValue: selection)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(CadenceSettingsTab.allCases) { tab in
                ProductionSettingsView(
                    model: model,
                    tab: tab,
                    updateController: updateController
                )
                .tabItem {
                    Label(tab.title, systemImage: tab.symbolName)
                }
                .tag(tab)
            }
        }
        .frame(width: 760, height: 640, alignment: .topLeading)
        .task(id: selection) {
            await Task.yield()
            NSApp.keyWindow?.title = "Settings"
        }
    }
}

enum CadenceLaunchEnvironment {
    static func shouldUsePreviewLibrary(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
