import SwiftUI

struct ProductionTagsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore

    @State private var taggedTracks: [LibraryTrackProjection] = []
    @State private var isLoadingTracks = false
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
            } else if store.tags.isEmpty,
                      model.selectedProductionTagEditingTrackID == nil {
                ContentUnavailableView(
                    "No Tags Yet",
                    systemImage: "tag",
                    description: Text(
                        "Your music is already here. Create a tag to start organizing it."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }

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
            Text("Tags")
                .font(.title2.bold())
                .padding(.horizontal, 18)
                .padding(.vertical, 20)

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
                ContentUnavailableView(
                    "Choose a Tag",
                    systemImage: "tag",
                    description: Text(
                        "Browse a tag or use the editor to assign one."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
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

                Text(selectedTag?.displayPath ?? "Tags")
                    .font(.largeTitle.bold())
                Text("\(taggedTracks.count) tracks")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
}
