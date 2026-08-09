import AppKit
import SwiftUI

@main
struct CadenceApp: App {
    @State private var model = Self.makeInitialModel()
    @State private var guideCoordinator = GuideCoordinator()
    @AppStorage("appearance")
    private var appearanceRawValue = CadenceAppearance.system.rawValue

    var body: some Scene {
        WindowGroup("Cadence") {
            CadenceRootView(
                model: model,
                guideCoordinator: guideCoordinator
            )
            .frame(minWidth: 1080, minHeight: 720)
            .preferredColorScheme(appearance.colorScheme)
            .tint(CadenceTheme.primaryAccent)
            .onChange(
                of: appearanceRawValue,
                initial: true
            ) { _, _ in
                NSApplication.shared.appearance =
                    appearance.appKitAppearance
            }
        }
        .defaultSize(width: 1512, height: 982)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
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

            CommandGroup(before: .help) {
                Button("Cadence Guide") {
                    guideCoordinator.presentChapterPicker()
                }
                .keyboardShortcut("?", modifiers: [.option, .command])
            }
        }
    }

    private var appearance: CadenceAppearance {
        CadenceAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private static func makeInitialModel() -> CadenceAppModel {
        if CadenceLaunchEnvironment.shouldUsePreviewLibrary() {
            return .production(librarySession: .preview())
        }
        return .production(librarySession: .startup())
    }
}

enum CadenceLaunchEnvironment {
    static func shouldUsePreviewLibrary(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
