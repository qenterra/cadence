import SwiftUI

struct TagsView: View {
    @Bindable var model: CadenceAppModel

    private let initialInspectorSearchQuery: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var inspectorWidth: CGFloat = 320

    init(
        model: CadenceAppModel,
        initialInspectorSearchQuery: String = ""
    ) {
        self.model = model
        self.initialInspectorSearchQuery = initialInspectorSearchQuery
    }

    var body: some View {
        Group {
            if model.librarySession.availability != .preview {
                ProductionTagsView(
                    model: model,
                    store: model.librarySession.store
                )
            } else if model.tracks.isEmpty {
                EmptyLibraryView(
                    title: "No Tracks to Tag",
                    description: "Import music before organizing it with tags."
                ) {
                    model.requestNavigationDestination(.importMusic)
                }
            } else {
                GeometryReader { geometry in
                    let layout = TagsWorkspaceLayout(
                        totalWidth: geometry.size.width,
                        isInspectorPresented: model.isTagInspectorPresented,
                        requestedInspectorWidth: inspectorWidth
                    )

                    ZStack(alignment: .trailing) {
                        workspace(layout: layout)

                        if layout.inspectorPresentation == .overlay {
                            TagEditorInspector(
                                model: model,
                                initialSearchQuery: initialInspectorSearchQuery
                            )
                            .frame(width: layout.inspectorWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .shadow(
                                color: .black.opacity(0.32),
                                radius: 24,
                                x: -8
                            )
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(inspectorBoundaryColor)
                                    .frame(
                                        width: contrast == .increased ? 2 : 1
                                    )
                            }
                            .transition(.opacity)
                            .zIndex(1)
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topTrailing
                    )
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.15),
                        value: layout.inspectorPresentation == .overlay
                    )
                }
            }
        }
        .background(CadenceTheme.contentBackground)
        .onExitCommand {
            if model.isTagInspectorPresented {
                model.isTagInspectorPresented = false
            }
        }
    }

    private func workspace(
        layout: TagsWorkspaceLayout
    ) -> some View {
        HStack(spacing: 0) {
            TagGroupsColumn(model: model)
                .frame(width: layout.columns.groups)
                .frame(maxHeight: .infinity, alignment: .top)

            TagsColumnDivider()

            TagsColumn(model: model)
                .frame(width: layout.columns.tags)
                .frame(maxHeight: .infinity, alignment: .top)

            TagsColumnDivider()

            TagResultsColumn(model: model)
                .frame(width: layout.columns.results)
                .frame(maxHeight: .infinity, alignment: .top)

            if layout.inspectorPresentation == .column {
                TagInspectorResizeHandle(width: $inspectorWidth)

                TagEditorInspector(
                    model: model,
                    initialSearchQuery: initialInspectorSearchQuery
                )
                .frame(width: layout.inspectorWidth)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var inspectorBoundaryColor: Color {
        contrast == .increased
            ? .primary.opacity(0.5)
            : CadenceTheme.separator
    }
}

struct TagsColumnDivider: View {
    var body: some View {
        Rectangle()
            .fill(CadenceTheme.separator)
            .frame(width: 1)
    }
}

struct TagsColumnWidths {
    let groups: CGFloat
    let tags: CGFloat
    let results: CGFloat

    init(totalWidth: CGFloat) {
        let availableWidth = max(totalWidth - 2, 930)
        let proposedGroups = (availableWidth * 0.21).clamped(to: 190 ... 240)
        let proposedTags = (availableWidth * 0.28).clamped(to: 250 ... 320)
        let proposedResults = availableWidth - proposedGroups - proposedTags

        if proposedResults >= 440 {
            groups = proposedGroups
            tags = proposedTags
            results = proposedResults
        } else {
            let deficit = 440 - proposedResults
            let groupCapacity = proposedGroups - 190
            let tagCapacity = proposedTags - 250
            let totalCapacity = groupCapacity + tagCapacity
            let groupReduction = totalCapacity > 0
                ? deficit * (groupCapacity / totalCapacity)
                : 0
            let tagReduction = deficit - groupReduction

            groups = max(proposedGroups - groupReduction, 190)
            tags = max(proposedTags - tagReduction, 250)
            results = max(availableWidth - groups - tags, 440)
        }
    }
}

enum TagInspectorPresentation: Hashable {
    case hidden
    case column
    case overlay
}

struct TagsWorkspaceLayout {
    static let inspectorWidthRange: ClosedRange<CGFloat> = 300 ... 360
    static let preferredInspectorWidth: CGFloat = 320

    let columns: TagsColumnWidths
    let inspectorPresentation: TagInspectorPresentation
    let inspectorWidth: CGFloat

    init(
        totalWidth: CGFloat,
        isInspectorPresented: Bool,
        requestedInspectorWidth: CGFloat = preferredInspectorWidth
    ) {
        let inspectorWidth = requestedInspectorWidth.clamped(
            to: Self.inspectorWidthRange
        )
        self.inspectorWidth = inspectorWidth

        guard isInspectorPresented else {
            inspectorPresentation = .hidden
            columns = TagsColumnWidths(totalWidth: totalWidth)
            return
        }

        let minimumColumnWorkspaceWidth: CGFloat = 932
        let canFitInspector = totalWidth - inspectorWidth - 1
            >= minimumColumnWorkspaceWidth

        if canFitInspector {
            inspectorPresentation = .column
            columns = TagsColumnWidths(
                totalWidth: totalWidth - inspectorWidth - 1
            )
        } else {
            inspectorPresentation = .overlay
            columns = TagsColumnWidths(totalWidth: totalWidth)
        }
    }
}

private struct TagInspectorResizeHandle: View {
    @Binding var width: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(
                contrast == .increased
                    ? Color.primary.opacity(0.5)
                    : CadenceTheme.separator
            )
            .frame(width: contrast == .increased ? 2 : 1)
            .overlay {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .gesture(resizeGesture)
            }
            .accessibilityElement()
            .accessibilityLabel("Resize Tag Editor")
            .accessibilityValue(Int(width).formatted())
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    width = (width + 10).clamped(
                        to: TagsWorkspaceLayout.inspectorWidthRange
                    )
                case .decrement:
                    width = (width - 10).clamped(
                        to: TagsWorkspaceLayout.inspectorWidthRange
                    )
                @unknown default:
                    break
                }
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .global
        )
        .onChanged { value in
            if dragStartWidth == nil {
                dragStartWidth = width
            }
            guard let dragStartWidth else {
                return
            }
            width = (dragStartWidth - value.translation.width).clamped(
                to: TagsWorkspaceLayout.inspectorWidthRange
            )
        }
        .onEnded { _ in
            dragStartWidth = nil
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
