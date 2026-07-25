import SwiftUI

struct SmartCollectionsView: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let widths = SmartCollectionsColumnWidths(
                totalWidth: geometry.size.width
            )

            HStack(spacing: 0) {
                SmartCollectionListColumn(model: model)
                    .frame(width: widths.collections)

                SmartCollectionsColumnDivider()

                workspace(widths: widths)
                    .frame(width: widths.content)
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
        }
        .background(CadenceTheme.contentBackground)
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
    private func workspace(
        widths: SmartCollectionsColumnWidths
    ) -> some View {
        switch model.smartCollectionsPresentationMode {
        case .listening:
            SmartCollectionListeningPage(model: model)
        case .editing:
            HStack(spacing: 0) {
                SmartCollectionRuleBuilder(model: model)
                    .frame(width: widths.builder)

                SmartCollectionsColumnDivider()

                SmartCollectionResultsColumn(model: model)
                    .frame(width: widths.results)
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

struct SmartCollectionsColumnWidths {
    let collections: CGFloat
    let content: CGFloat
    let builder: CGFloat
    let results: CGFloat

    init(totalWidth: CGFloat) {
        let availableWidth = max(totalWidth - 1, 1005)
        collections = (availableWidth * 0.18).clamped(to: 230 ... 260)
        content = availableWidth - collections
        builder = (availableWidth * 0.32).clamped(to: 390 ... 460)
        results = content - builder - 1
    }
}

private struct SmartCollectionsColumnDivider: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(
                contrast == .increased
                    ? .primary.opacity(0.42)
                    : CadenceTheme.separator
            )
            .frame(width: 1)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
