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
                        "Items removed from the managed library appear here."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.trashOperations) { operation in
                            trashRow(operation)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(CadenceTheme.contentBackground)
        .confirmationDialog(
            "Empty Trash Permanently?",
            isPresented: $confirmsEmptyTrash
        ) {
            Button("Empty Trash", role: .destructive) {
                Task {
                    await model.emptyProductionTrash()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Managed audio, artwork, and lyrics in Trash cannot be recovered."
            )
        }
        .confirmationDialog(
            "Delete This Item Permanently?",
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
            Button("Cancel", role: .cancel) {
                pendingPermanentDeletion = nil
            }
        } message: { operation in
            Text(
                "\(operation.itemCount) tracks and their managed files "
                    + "will be removed permanently."
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
                Text(operation.targetKind.title)
                    .font(.body.weight(.medium))
                Text(
                    "\(operation.itemCount) tracks · "
                        + operation.createdAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                )
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
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(CadenceTheme.hoverFill)
        .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup))
    }
}

private extension TrashTargetKind {
    var title: String {
        switch self {
        case .track: "Removed Track"
        case .album: "Removed Album"
        case .artist: "Removed Artist"
        }
    }

    var symbolName: String {
        switch self {
        case .track: "music.note"
        case .album: "square.stack"
        case .artist: "person"
        }
    }
}
