import SwiftUI

struct ProductionTagsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore

    @State private var taggedTracks: [LibraryTrackProjection] = []
    @State private var isLoadingTracks = false
    @State private var tagDialog: ProductionTagDialog?
    @State private var newTagPath = ""
    @State private var isTrackPickerPresented = false
    @AppStorage("tags.sidebarWidth")
    private var sidebarWidth = 300.0
    @AppStorage("tags.inspectorWidth")
    private var inspectorWidth = 330.0

    var body: some View {
        Group {
            if store.catalogCounts.liveTrackCount == 0, store.tracks.isEmpty {
                EmptyLibraryView(
                    title: "No Tracks to Tag",
                    description: "Import music before organizing it with tags."
                ) {
                    model.requestNavigationDestination(.importMusic)
                }
            } else {
                if let trackID = model.selectedProductionTagEditingTrackID {
                    CadenceResizableSplitView(
                        fixedPane: .trailing,
                        fixedWidth: $inspectorWidth,
                        fixedMinimum: 280,
                        fixedMaximum: 460,
                        flexibleMinimum: 480
                    ) {
                        workspace
                    } trailing: {
                        ProductionTagEditorInspector(
                            model: model,
                            store: store,
                            trackID: trackID
                        )
                    }
                } else {
                    workspace
                }
            }
        }
        .background(CadenceTheme.contentBackground)
        .sheet(isPresented: $isTrackPickerPresented) {
            if let selectedTag {
                TagTrackPickerSheet(
                    model: model,
                    store: store,
                    tag: selectedTag
                )
            }
        }
        .task(id: "\(selectedTagID?.uuidString ?? "none")-\(store.tagRevision)") {
            guard let selectedTagID else {
                taggedTracks = []
                return
            }
            isLoadingTracks = true
            taggedTracks = await store.tracks(tagID: selectedTagID)
            isLoadingTracks = false
        }
        .alert(
            tagDialog?.title ?? "Tag",
            isPresented: tagDialogPresented
        ) {
            switch tagDialog {
            case .create:
                TextField("Tag or group/subtag", text: $newTagPath)
                Button("Create") {
                    createTag()
                }
                .disabled(
                    newTagPath.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
                Button("Cancel", role: .cancel) {
                    tagDialog = nil
                }
            case .error, nil:
                Button("OK") {
                    tagDialog = nil
                }
            }
        } message: {
            if case let .error(message) = tagDialog {
                Text(message)
            } else {
                Text("Use a standalone tag or one level such as mood/calm.")
            }
        }
    }
}

private extension ProductionTagsView {
    private var workspace: some View {
        CadenceResizableSplitView(
            fixedPane: .leading,
            fixedWidth: $sidebarWidth,
            fixedMinimum: WorkspaceLayout.paneMinimumWidth,
            fixedMaximum: WorkspaceLayout.paneMaximumWidth,
            flexibleMinimum: 360
        ) {
            tagSidebar
        } trailing: {
            tagResults
        }
    }

    private var tagSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspacePaneHeader("Tags") {
                Button {
                    newTagPath = ""
                    tagDialog = .create
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Tag")
            }

            ScrollView(.vertical) {
                LazyVStack(spacing: 4) {
                    ForEach(store.tags) { tag in
                        tagButton(tag)
                            .task {
                                guard tag.id == store.tags.last?.id else {
                                    return
                                }
                                await store.loadNextTags()
                            }
                    }
                }
                .padding(.horizontal, WorkspaceLayout.listInset)
                .padding(.top, WorkspaceLayout.listInset)
                .padding(.bottom, 16)
            }
        }
    }

    private var tagResults: some View {
        VStack(alignment: .leading, spacing: 18) {
            resultHeader

            if isLoadingTracks {
                ProgressView("Loading Tracks")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedTagID == nil {
                if store.tags.isEmpty {
                    ContentUnavailableView {
                        Label("No Tags Yet", systemImage: "tag")
                    } description: {
                        Text(
                            "Create a tag, then assign it to tracks or albums."
                        )
                    } actions: {
                        Button("New Tag", systemImage: "plus") {
                            newTagPath = ""
                            tagDialog = .create
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "Choose a Tag",
                        systemImage: "tag",
                        description: Text(
                            "Browse a tag or use the editor to assign one."
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if taggedTracks.isEmpty {
                ContentUnavailableView(
                    "No Matching Tracks",
                    systemImage: "music.note",
                    description: Text(
                        "Nothing currently matches \(selectedTag?.displayPath ?? "this tag")."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProductionTrackList(
                    model: model,
                    tracks: taggedTracks,
                    context: selectedTagID.map(TrackTableContext.tag)
                        ?? .library
                )
            }
        }
        .padding(WorkspaceLayout.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var resultHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.hasContextualBackNavigation {
                Button {
                    model.requestContextualBack()
                } label: {
                    Label(
                        "Back to \(model.contextualBackTitle)",
                        systemImage: "chevron.left"
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            CadencePageHeader(
                selectedTag?.displayPath ?? "Tags",
                subtitle: "\(taggedTracks.count) tracks"
            ) {
                if selectedTag != nil {
                    Button("Add Tracks", systemImage: "plus") {
                        isTrackPickerPresented = true
                    }
                }
            }
        }
    }

    private func tagButton(
        _ tag: LibraryTagProjection
    ) -> some View {
        Button {
            model.selectedProductionTagID = tag.id
        } label: {
            HStack {
                Image(systemName: "tag")
                    .frame(width: 24)
                Text(tag.displayPath)
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(
                selectedTagID == tag.id ? .primary : .secondary
            )
            .padding(.horizontal, 12)
            .frame(height: WorkspaceLayout.rowHeight)
            .background {
                BrowserRowSurface(
                    isSelected: selectedTagID == tag.id,
                    isHovered: false,
                    isFocused: false
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CadenceRowButtonStyle())
    }

    private var selectedTagID: UUID? {
        model.selectedProductionTagID ?? store.tags.first?.id
    }

    private var selectedTag: LibraryTagProjection? {
        guard let selectedTagID else {
            return nil
        }
        return store.tags.first { $0.id == selectedTagID }
    }

    private var tagDialogPresented: Binding<Bool> {
        Binding(
            get: { tagDialog != nil },
            set: { isPresented in
                if !isPresented {
                    tagDialog = nil
                }
            }
        )
    }

    private func createTag() {
        let path = newTagPath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !path.isEmpty else {
            return
        }
        tagDialog = nil
        Task {
            do {
                if let tagID = try await store.createTag(
                    displayPath: path
                ) {
                    model.selectedProductionTagID = tagID
                }
                newTagPath = ""
            } catch {
                tagDialog = .error(error.localizedDescription)
            }
        }
    }
}

private enum ProductionTagDialog {
    case create
    case error(String)

    var title: String {
        switch self {
        case .create:
            "New Tag"
        case .error:
            "Couldn’t Create Tag"
        }
    }
}
