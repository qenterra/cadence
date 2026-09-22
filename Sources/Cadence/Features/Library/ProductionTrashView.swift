import SwiftUI

struct ProductionTrashView: View {
    @Bindable var model: CadenceAppModel
    @State private var confirmsEmptyTrash = false
    @State private var pendingPermanentDeletion:
        LibraryTrashProjection?

    private var store: LibraryStore {
        model.librarySession.store
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            CadenceSeparator()
            if store.trashOperations.isEmpty {
                ContentUnavailableView(
                    "Trash Is Empty",
                    systemImage: "trash",
                    description: Text(
                        "Tracks, albums, and artists you remove appear here."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 4) {
                        ForEach(store.trashOperations) { operation in
                            trashRow(operation)
                        }
                    }
                    .padding(24)
                }
                .refreshable {
                    await store.refresh(.trash)
                }
            }
        }
        .background(CadenceTheme.contentBackground)
        .confirmationDialog(
            "Empty Trash?",
            isPresented: $confirmsEmptyTrash
        ) {
            Button("Empty Trash", role: .destructive) {
                Task {
                    await model.emptyProductionTrash()
                }
            }
            .cadenceActionTint(.destructive)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently deletes the music, artwork, and lyrics in Trash."
            )
        }
        .confirmationDialog(
            "Delete This Item?",
            isPresented: Binding(
                get: { pendingPermanentDeletion != nil },
                set: {
                    if !$0 {
                        pendingPermanentDeletion = nil
                    }
                }
            ),
            presenting: pendingPermanentDeletion
        ) { operation in
            Button("Delete Permanently", role: .destructive) {
                Task {
                    await model.permanentlyDeleteProductionTrash(
                        operationID: operation.id
                    )
                }
                pendingPermanentDeletion = nil
            }
            .cadenceActionTint(.destructive)
            Button("Cancel", role: .cancel) {
                pendingPermanentDeletion = nil
            }
        } message: { operation in
            Text(
                "This permanently deletes \(operation.itemCount) tracks and their files."
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Trash")
                    .font(.largeTitle.bold())
                Text(
                    "\(store.catalogCounts.trashedTrackCount) tracks"
                )
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Empty Trash…", role: .destructive) {
                confirmsEmptyTrash = true
            }
            .cadenceActionTint(.destructive)
            .disabled(store.trashOperations.isEmpty)
        }
        .padding(.horizontal, 28)
        .frame(height: 92)
    }

    private func trashRow(
        _ operation: LibraryTrashProjection
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: operation.targetKind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(CadenceTheme.subduedFill, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(operation.displayTitle)
                    .font(.body.weight(.medium))
                Text([
                    operation.displaySubtitle,
                    "\(operation.itemCount) tracks",
                    operation.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    ),
                ].compactMap(\.self).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") {
                Task {
                    await model.restoreProductionTrash(
                        operationID: operation.id
                    )
                }
            }
            .buttonStyle(.borderless)
            Button("Delete Permanently…", role: .destructive) {
                pendingPermanentDeletion = operation
            }
            .buttonStyle(.borderless)
            .cadenceActionTint(.destructive)
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(CadenceTheme.hoverFill)
        .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup))
    }
}

private extension TrashTargetKind {
    var symbolName: String {
        switch self {
        case .track: "music.note"
        case .album: "square.stack"
        case .artist: "person"
        }
    }
}
