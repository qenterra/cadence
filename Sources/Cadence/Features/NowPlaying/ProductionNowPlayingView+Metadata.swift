import QenTerraComponents
import SwiftUI

struct NowPlayingTagEntryState: Equatable, Sendable {
    private(set) var isEditing = false

    var presentation: NowPlayingTagEntryPresentation {
        NowPlayingTagEntryPresentation(
            showsAddButton: !isEditing,
            showsTextField: isEditing,
            requestsFocus: isEditing
        )
    }

    mutating func beginEditing() {
        isEditing = true
    }

    mutating func cancelEditing() {
        isEditing = false
    }

    func submission(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct NowPlayingTagEntryPresentation: Equatable, Sendable {
    let showsAddButton: Bool
    let showsTextField: Bool
    let requestsFocus: Bool
}

extension ProductionNowPlayingView {
    var trackTags: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .frame(height: 24)

                    DesignFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(tagStates) { state in
                            CadenceTagPill(
                                title: state.tag.displayPath,
                                removeAction: {
                                    removeTag(state)
                                },
                                removeAccessibilityLabel: "Remove "
                                    + state.tag.displayPath
                                    + " from Track",
                                action: {
                                    tagBeingEdited = state.tag
                                }
                            )
                            .help("Edit " + state.tag.displayPath)
                        }

                        if tagEntryState.presentation.showsTextField {
                            TextField("Tag name", text: $newTagPath)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .frame(width: 110, height: 24)
                                .focused($isTagEntryFocused)
                                .onSubmit(addTag)
                                .onExitCommand(perform: cancelTagEntry)
                                .disabled(isAddingTag)
                                .accessibilityLabel("Tag Name")
                        } else {
                            Button(action: beginTagEntry) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(
                                width: 26,
                                height: CadenceTagPillMetrics.height
                            )
                            .help("Add Tag")
                            .accessibilityLabel("Add Tag")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 36)
                .background(
                    CadenceTheme.subduedFill,
                    in: RoundedRectangle(
                        cornerRadius: CadenceTheme.radiusControl,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: CadenceTheme.radiusControl,
                        style: .continuous
                    )
                    .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
                }

                Button {
                    model.presentTrackMetadataEditor(track)
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(minHeight: 34)
                        .padding(.horizontal, 10)
                        .background(
                            CadenceTheme.subduedFill,
                            in: RoundedRectangle(
                                cornerRadius: CadenceTheme.radiusControl,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
                .help("Edit Information")
                .accessibilityLabel("Edit Information for \(displayedTrackTitle)")
            }

            if let tagError {
                Text(tagError)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var externalFileNotice: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Playing external file", systemImage: "play.rectangle")
                .font(.caption.weight(.semibold))
            Text("This file is playing without being added to your library.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            CadenceTheme.subduedFill,
            in: RoundedRectangle(
                cornerRadius: CadenceTheme.radiusControl,
                style: .continuous
            )
        )
    }

    var trimmedTagPath: String {
        tagEntryState.submission(from: newTagPath) ?? ""
    }

    func beginTagEntry() {
        tagEntryState.beginEditing()
        tagError = nil
        Task { @MainActor in
            await Task.yield()
            isTagEntryFocused = true
        }
    }

    func cancelTagEntry() {
        guard !isAddingTag else {
            return
        }
        newTagPath = ""
        tagError = nil
        isTagEntryFocused = false
        tagEntryState.cancelEditing()
    }

    func addTag() {
        let path = trimmedTagPath
        guard !path.isEmpty else {
            return
        }
        Task { @MainActor in
            isAddingTag = true
            defer { isAddingTag = false }
            do {
                _ = try await model.librarySession.store.createTagAndAssign(
                    displayPath: path,
                    trackID: track.id
                )
                newTagPath = ""
                tagError = nil
                tagStates = try await model.librarySession.store.tagStates(
                    trackID: track.id
                )
                isTagEntryFocused = false
                tagEntryState.cancelEditing()
            } catch {
                tagError = error.localizedDescription
                isTagEntryFocused = true
            }
        }
    }

    func removeTag(_ state: ProductionTrackTagState) {
        Task { @MainActor in
            do {
                try await model.librarySession.store.setTag(
                    state.tag.id,
                    assigned: false,
                    trackID: track.id
                )
                tagStates = try await model.librarySession.store.tagStates(
                    trackID: track.id
                )
                tagError = nil
            } catch {
                tagError = error.localizedDescription
            }
        }
    }

    func renameTag(
        _ tag: LibraryTagProjection,
        displayPath: String
    ) async -> Bool {
        do {
            _ = try await model.librarySession.store.renameTag(
                id: tag.id,
                displayPath: displayPath
            )
            tagStates = try await model.librarySession.store.tagStates(
                trackID: track.id
            )
            tagError = nil
            return true
        } catch {
            tagError = error.localizedDescription
            return false
        }
    }
}
