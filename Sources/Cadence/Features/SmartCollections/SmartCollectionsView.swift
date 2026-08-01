import SwiftUI

enum SmartCollectionsPaneConstraints {
    static let list = (
        minimum: WorkspaceLayout.paneMinimumWidth,
        ideal: CGFloat(270),
        maximum: WorkspaceLayout.paneMaximumWidth
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
        .task(id: smartCollectionDataRequest) {
            guard model.librarySession.availability != .preview else {
                return
            }
            await model.librarySession.store.loadSmartCollectionRuleData()
            await model.librarySession.store.loadSmartCollectionSummaries(
                rules: model.smartCollections.map(\.rule)
            )
        }
        .task(id: selectedResultRequest) {
            guard
                model.librarySession.availability != .preview,
                let rule = model.selectedSmartCollection?.rule
            else {
                return
            }
            await model.librarySession.store.loadSmartCollectionResult(
                rule: rule
            )
        }
        .task(id: draftResultRequest) {
            guard
                model.librarySession.availability != .preview,
                let draft = model.smartCollectionDraft,
                model.smartCollectionValidation.isValid
            else {
                return
            }
            await model.librarySession.store.loadSmartCollectionResult(
                rule: draft.rule
            )
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

    private var smartCollectionDataRequest: SmartCollectionDataRequest {
        SmartCollectionDataRequest(
            tagRevision: model.librarySession.store.tagRevision,
            collections: model.smartCollections
        )
    }

    private var selectedResultRequest: SmartCollectionResultRequest? {
        model.selectedSmartCollection.map {
            SmartCollectionResultRequest(
                tagRevision: model.librarySession.store.tagRevision,
                rule: $0.rule
            )
        }
    }

    private var draftResultRequest: SmartCollectionResultRequest? {
        model.smartCollectionDraft.map {
            SmartCollectionResultRequest(
                tagRevision: model.librarySession.store.tagRevision,
                rule: $0.rule
            )
        }
    }
}

private struct SmartCollectionDataRequest: Hashable {
    let tagRevision: Int
    let collections: [SmartCollectionPreview]
}

private struct SmartCollectionResultRequest: Hashable {
    let tagRevision: Int
    let rule: SmartCollectionRuleGroup
}
