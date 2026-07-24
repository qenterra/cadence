import SwiftUI

@main
struct CadenceApp: App {
    @State private var model = CadenceAppModel()

    var body: some Scene {
        WindowGroup("Cadence") {
            CadenceRootView(model: model)
                .frame(minWidth: 1080, minHeight: 720)
                .preferredColorScheme(.dark)
                .tint(CadenceTheme.accent)
        }
        .defaultSize(width: 1512, height: 982)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
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
                    model.saveSmartCollectionDraft()
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
}
