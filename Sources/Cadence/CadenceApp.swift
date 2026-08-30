import AppKit
import SwiftUI

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(CadenceApplicationDelegate.self)
    private var applicationDelegate
    @State private var model: CadenceAppModel
    private let instanceCoordinator = CadenceInstanceCoordinator.shared
    private let appearanceController = AppearanceController()
    private let notificationController: CadenceNotificationController
    @State private var updateController: CadenceUpdateController
    @AppStorage("appearance")
    private var appearanceRawValue = CadenceAppearance.system.rawValue

    init() {
        CadencePreferences.registerDefaults()
        let notificationController = CadenceNotificationController()
        self.notificationController = notificationController
        _model = State(
            initialValue: Self.makeInitialModel(
                notificationController: notificationController
            )
        )
        _updateController = State(
            initialValue: CadenceUpdateController(
                startsUpdater:
                !CadenceLaunchEnvironment.shouldUsePreviewLibrary(),
                notificationController: notificationController
            )
        )
    }

    var body: some Scene {
        Window("Cadence", id: "main") {
            Group {
                if !CadenceLaunchEnvironment.shouldEnforceSingleInstance()
                    || instanceCoordinator.claim() == .owner {
                    CadenceRootView(model: model)
                } else {
                    Color.clear
                }
            }
            .frame(
                minWidth: AdaptiveLayoutPolicy.minimumWindowSize.width,
                minHeight: AdaptiveLayoutPolicy.minimumWindowSize.height
            )
            .tint(CadenceTheme.primaryAccent)
            .onChange(
                of: appearanceRawValue,
                initial: true
            ) { _, _ in
                appearanceController.apply(appearance)
            }
            .task {
                let openHandler: ([URL]) -> Void = { urls in
                    Task { @MainActor in
                        await model.openExternalAudio(urls: urls)
                    }
                }
                if CadenceLaunchEnvironment.shouldEnforceSingleInstance() {
                    applicationDelegate.connect(
                        instanceCoordinator: instanceCoordinator,
                        handler: openHandler,
                        terminateDuplicate: { NSApp.terminate(nil) }
                    )
                } else {
                    applicationDelegate.connect(openHandler)
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
                updateController: updateController,
                notificationController: notificationController
            )
            .tint(CadenceTheme.primaryAccent)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

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

    private static func makeInitialModel(
        notificationController: CadenceNotificationController
    ) -> CadenceAppModel {
        if CadenceLaunchEnvironment.shouldUsePreviewLibrary() {
            return .preview()
        }
        guard CadenceInstanceCoordinator.shared.claim() == .owner else {
            return .preview()
        }
        return .production(
            librarySession: .startup(),
            notificationController: notificationController
        )
    }
}

struct CadenceSettingsWindow: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CadenceAppModel
    let updateController: CadenceUpdateController
    let notificationController: CadenceNotificationController
    let defaultAudioApplication: DefaultAudioApplicationController?
    @State private var selection: CadenceSettingsTab

    init(
        model: CadenceAppModel,
        updateController: CadenceUpdateController,
        notificationController: CadenceNotificationController =
            CadenceNotificationController(),
        defaultAudioApplication: DefaultAudioApplicationController? = nil,
        selection: CadenceSettingsTab = .general
    ) {
        self.model = model
        self.updateController = updateController
        self.notificationController = notificationController
        self.defaultAudioApplication = defaultAudioApplication
        _selection = State(initialValue: selection)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabStrip(selection: $selection)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, CadenceLayout.contentGap)
                .padding(.vertical, CadenceLayout.compactGap)
                .cadenceGlassSurface(
                    cornerRadius: CadenceTheme.radiusControl
                )

            CadenceSeparator()

            ProductionSettingsView(
                model: model,
                tab: selection,
                updateController: updateController,
                notificationController: notificationController,
                defaultAudioApplication: defaultAudioApplication,
                openDestination: { destination in
                    model.requestNavigationDestination(destination)
                    dismiss()
                }
            )
        }
        .frame(width: 840, height: 680, alignment: .top)
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

    static func shouldEnforceSingleInstance(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        !shouldUsePreviewLibrary(environment: environment)
    }
}
