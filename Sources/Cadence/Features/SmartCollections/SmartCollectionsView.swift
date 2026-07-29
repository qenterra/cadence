import SwiftUI

enum SmartCollectionsPaneConstraints {
    static let list = (
        minimum: CGFloat(220),
        ideal: CGFloat(250),
        maximum: CGFloat(380)
    )
    static let workspaceMinimum = CGFloat(720)
    static let builder = (
        minimum: CGFloat(360),
        ideal: CGFloat(430),
        maximum: CGFloat(620)
    )
    static let resultsMinimum = CGFloat(360)
}

struct SmartCollectionsView: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("smartCollections.listWidth")
    private var listWidth = Double(
        SmartCollectionsPaneConstraints.list.ideal
    )
    @AppStorage("smartCollections.builderWidth")
    private var builderWidth = Double(
        SmartCollectionsPaneConstraints.builder.ideal
    )

    var body: some View {
        CadenceResizableSplitView(
            fixedPane: .leading,
            fixedWidth: $listWidth,
            fixedMinimum: SmartCollectionsPaneConstraints.list.minimum,
            fixedMaximum: SmartCollectionsPaneConstraints.list.maximum,
            flexibleMinimum: 560
        ) {
            SmartCollectionListColumn(model: model)
        } trailing: {
            workspace
                .id(model.smartCollectionsPresentationMode)
                .transition(.opacity)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: model.smartCollectionsPresentationMode
        )
        .background(CadenceTheme.contentBackground)
        .task(id: model.librarySession.store.tagRevision) {
            guard model.librarySession.availability != .preview else {
                return
            }
            await model.librarySession.store.loadSmartCollectionIndex()
        }
        .onExitCommand {
            guard
                model.smartCollectionsPresentationMode == .editing,
                !model.isSmartCollectionDraftDirty
            else {
                return
            }
            model.requestFinishSmartCollectionEditing()
        }
        .alert(
            "Save Changes?",
            isPresented: pendingSwitchBinding
        ) {
            Button("Save") {
                model.resolvePendingSmartCollectionTransition(.save)
            }
            .disabled(!model.canSaveSmartCollectionDraft)

            Button("Discard", role: .destructive) {
                model.resolvePendingSmartCollectionTransition(.discard)
            }

            Button("Cancel", role: .cancel) {
                model.resolvePendingSmartCollectionTransition(.cancel)
            }
        } message: {
            Text(
                "This Smart Collection has unsaved changes."
            )
        }
        .alert(
            "Delete Smart Collection?",
            isPresented: pendingDeletionBinding
        ) {
            Button("Delete", role: .destructive) {
                model.confirmDeleteSmartCollection()
            }

            Button("Cancel", role: .cancel) {
                model.cancelDeleteSmartCollection()
            }
        } message: {
            Text("This removes the collection definition from this session.")
        }
    }

    @ViewBuilder
    private var workspace: some View {
        switch model.smartCollectionsPresentationMode {
        case .listening:
            SmartCollectionListeningPage(model: model)
        case .editing:
            CadenceResizableSplitView(
                fixedPane: .leading,
                fixedWidth: $builderWidth,
                fixedMinimum: SmartCollectionsPaneConstraints.builder.minimum,
                fixedMaximum: SmartCollectionsPaneConstraints.builder.maximum,
                flexibleMinimum: SmartCollectionsPaneConstraints.resultsMinimum
            ) {
                SmartCollectionRuleBuilder(model: model)
            } trailing: {
                SmartCollectionResultsColumn(model: model)
            }
        }
    }

    private var pendingSwitchBinding: Binding<Bool> {
        Binding(
            get: { model.pendingSmartCollectionTransition != nil },
            set: { isPresented in
                if !isPresented, model.pendingSmartCollectionTransition != nil {
                    model.resolvePendingSmartCollectionTransition(.cancel)
                }
            }
        )
    }

    private var pendingDeletionBinding: Binding<Bool> {
        Binding(
            get: { model.pendingSmartCollectionDeletionID != nil },
            set: { isPresented in
                if !isPresented {
                    model.cancelDeleteSmartCollection()
                }
            }
        )
    }
}
