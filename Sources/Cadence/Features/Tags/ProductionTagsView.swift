import SwiftUI

struct ProductionTagsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore

    @State private var taggedTracks: [LibraryTrackProjection] = []
    @State private var isLoadingTracks = false
    @State private var tagDialog: ProductionTagDialog?
    @State private var newTagPath = ""
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
            fixedMinimum: 220,
            fixedMaximum: 420,
            flexibleMinimum: 360
        ) {
            tagSidebar
        } trailing: {
            tagResults
        }
    }

    private var tagSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tags")
                    .font(.title2.bold())
                Spacer()
                Button {
                    newTagPath = ""
                    tagDialog = .create
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Tag")
            }
            .padding(.horizontal, 18)
            .frame(height: 68)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.tags) { tag in
                        tagButton(tag)
                    }
                }
                .padding(.horizontal, 10)
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
                ScrollView {
                    ProductionTrackList(
                        model: model,
                        tracks: taggedTracks
                    )
                }
            }
        }
        .padding(24)
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
            )
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
            .frame(height: 46)
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
