import SwiftUI

struct TagEditorSearch: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.undoManager) private var undoManager
    @FocusState private var isFocused: Bool
    @State private var query: String

    init(
        model: CadenceAppModel,
        initialQuery: String = ""
    ) {
        self.model = model
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TagEditorSectionHeader("Assign Tag")

            TextField(searchPlaceholder, text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(commitQuery)
                .accessibilityLabel("Search or create tag")

            if !trimmedQuery.isEmpty {
                searchResults
            } else if model.tags.isEmpty {
                Text("Enter a path such as mood/calm to create the first tag.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: model.tagEditingSelection.targets) {
            query = ""
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if !matchingTags.isEmpty {
            VStack(spacing: 4) {
                ForEach(Array(matchingTags.prefix(5))) { tag in
                    Button {
                        assign(tag)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "tag")
                                .foregroundStyle(.secondary)

                            Text(tag.displayPath)
                                .lineLimit(1)

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(CadenceTheme.subduedFill, in: .rect(cornerRadius: 7))
                }
            }
        }

        if let newTag {
            Button {
                createAndAssign(newTag)
            } label: {
                Label("Create “\(newTag.id)”", systemImage: "plus")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(CadenceTheme.subduedFill, in: .rect(cornerRadius: 7))
        } else if let validationError {
            Label(validationError.message, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchPlaceholder: String {
        model.tags.isEmpty
            ? "Create your first tag"
            : "Search or create tag"
    }

    private var matchingTags: [TagPreview] {
        guard !trimmedQuery.isEmpty else {
            return []
        }
        return model.tags.filter {
            $0.id.localizedStandardContains(trimmedQuery)
                || $0.displayPath.localizedStandardContains(trimmedQuery)
        }
        .sorted {
            $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
        }
    }

    private var validationError: TagPathValidationError? {
        guard !trimmedQuery.isEmpty else {
            return nil
        }
        return TagPreview.validationError(for: trimmedQuery)
    }

    private var newTag: TagPreview? {
        guard
            validationError == nil,
            let tag = TagPreview(path: trimmedQuery),
            !model.tags.contains(where: { $0.id == tag.id })
        else {
            return nil
        }
        return tag
    }

    private func commitQuery() {
        if let exactMatch = matchingTags.first(where: { $0.id == TagPreview(path: trimmedQuery)?.id }) {
            assign(exactMatch)
        } else if let firstMatch = matchingTags.first {
            assign(firstMatch)
        } else if let newTag {
            createAndAssign(newTag)
        }
    }

    private func assign(_ tag: TagPreview) {
        model.performTagEdit(
            .assign(
                tagID: tag.id,
                targets: model.tagEditingSelection.targets
            ),
            undoManager: undoManager
        )
        query = ""
    }

    private func createAndAssign(_ tag: TagPreview) {
        model.performTagEdit(
            .createAndAssign(
                path: tag.id,
                targets: model.tagEditingSelection.targets
            ),
            undoManager: undoManager
        )
        query = ""
    }
}
