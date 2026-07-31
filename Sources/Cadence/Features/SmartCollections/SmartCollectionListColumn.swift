import SwiftUI

struct SmartCollectionListColumn: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.smartCollectionListItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.smartCollectionListItems) { item in
                            SmartCollectionListRow(
                                model: model,
                                item: item
                            )
                        }
                    }
                    .padding(.horizontal, WorkspaceLayout.listInset)
                    .padding(.top, WorkspaceLayout.listInset)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        WorkspacePaneHeader("Smart Collections") {
            Button {
                model.requestNewSmartCollection()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Smart Collection")
            .accessibilityLabel("New Smart Collection")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Smart Collections", systemImage: "sparkles.rectangle.stack")
        } description: {
            Text("Build a live track view from tags and metadata.")
        } actions: {
            Button("New Collection") {
                model.requestNewSmartCollection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SmartCollectionListRow: View {
    @Bindable var model: CadenceAppModel

    let item: SmartCollectionListItem

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            guard !item.isTransient else {
                return
            }
            model.requestSelectSmartCollection(item.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.isTransient ? "circle.dotted" : "music.note.list")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.isSelected ? .primary : .tertiary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.body.weight(item.isSelected ? .medium : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(matchSummary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                Spacer(minLength: 6)

                if item.isTransient {
                    Text("Draft")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: WorkspaceLayout.rowHeight)
            .background {
                BrowserRowSurface(
                    isSelected: item.isSelected,
                    isHovered: isHovered,
                    isFocused: isFocused
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CadenceRowButtonStyle())
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .contextMenu {
            if !item.isTransient {
                Button("Edit Rules", systemImage: "slider.horizontal.3") {
                    model.requestEditSmartCollection(item.id)
                }

                Button("Rename", systemImage: "pencil") {
                    model.requestRenameSmartCollection(item.id)
                }

                Divider()

                Button("Delete", systemImage: "trash", role: .destructive) {
                    model.requestDeleteSmartCollection(item.id)
                }
            }
        }
        .accessibilityLabel(displayName)
        .accessibilityValue(
            "\(matchSummary), \(item.isSelected ? "Selected" : "Not selected")"
        )
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    }

    private var displayName: String {
        item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Collection"
            : item.name
    }

    private var matchSummary: String {
        let noun = item.matchCount == 1 ? "track" : "tracks"
        return "\(item.matchCount) \(noun) · \(durationText)"
    }

    private var durationText: String {
        let totalMinutes = max(Int(item.totalDuration.rounded()) / 60, 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes) min"
    }
}
