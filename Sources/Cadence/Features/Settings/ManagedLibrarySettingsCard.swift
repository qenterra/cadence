import AppKit
import SwiftUI

struct ManagedLibrarySettingsCard: View {
    @Bindable var model: CadenceAppModel
    let openDestination: ((NavigationDestination) -> Void)?
    @State private var libraryStorageSize = "Calculating…"
    @State private var isDeleteConfirmationPresented = false

    private var store: LibraryStore {
        model.librarySession.store
    }

    init(
        model: CadenceAppModel,
        openDestination: ((NavigationDestination) -> Void)? = nil
    ) {
        self.model = model
        self.openDestination = openDestination
    }

    var body: some View {
        SettingsCard(
            title: "Storage",
            symbol: "externaldrive"
        ) {
            libraryDetails
            libraryActions
            deletionAction
            relocationProgress
        }
        .task(id: "\(libraryPath)|\(model.libraryResetRevision)") {
            libraryStorageSize = await LibraryPackageSize.formatted(
                at: model.librarySession.location?.packageURL
            )
        }
        .confirmationDialog(
            "Delete your library?",
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button("Delete Library", role: .destructive) {
                Task { await model.deleteEntireManagedLibrary() }
            }
            .cadenceActionTint(.destructive)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Playback will stop and the Cadence folder will move to Trash. You can recover it there."
            )
        }
        .alert(
            "Library deleted",
            isPresented: Binding(
                get: { model.libraryResetNotice != nil },
                set: {
                    if !$0 {
                        model.dismissLibraryResetNotice()
                    }
                }
            )
        ) {
            Button("Done", role: .cancel) {
                model.dismissLibraryResetNotice()
            }
        } message: {
            Text(
                model.libraryResetNotice
                    ?? "Your previous library is in Trash."
            )
        }
    }

    @ViewBuilder
    private var libraryDetails: some View {
        LabeledContent("Location") {
            Text(libraryPath)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        LabeledContent("Tracks") {
            Text(store.catalogCounts.liveTrackCount.formatted())
        }
        LabeledContent("In Trash") {
            Text(store.catalogCounts.trashedTrackCount.formatted())
        }
        LabeledContent("Size on Disk") {
            Text(libraryStorageSize)
                .monospacedDigit()
        }
    }

    private var libraryActions: some View {
        HStack {
            Button("Import Music…", systemImage: "folder.badge.plus") {
                navigate(to: .importMusic)
            }
            Button("View Trash", systemImage: "trash") {
                navigate(to: .trash)
            }
            Button("Move Library…", systemImage: "externaldrive.badge.plus") {
                model.chooseLibraryLocation()
            }
            .disabled(model.isMovingLibrary)
            Button("Show in Finder", systemImage: "folder") {
                guard let packageURL = model.librarySession.location?.packageURL else {
                    return
                }
                NSWorkspace.shared.activateFileViewerSelecting([packageURL])
            }
            .disabled(model.librarySession.location == nil)
        }
    }

    private var deletionAction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(
                "Delete Library…",
                systemImage: "trash.slash",
                role: .destructive
            ) {
                isDeleteConfirmationPresented = true
            }
            .cadenceActionTint(.destructive)
            .disabled(
                model.librarySession.location == nil
                    || model.isMovingLibrary
                    || model.isResettingLibrary
            )

            Text("Moves the Cadence folder to Trash without touching the files you originally imported.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var relocationProgress: some View {
        if let progress = model.libraryRelocationProgress {
            VStack(alignment: .leading, spacing: 6) {
                Text(progress.phase.title)
                    .font(.callout.weight(.medium))
                if let fraction = progress.fractionCompleted {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(progress.label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var libraryPath: String {
        model.librarySession.location?.packageURL.path
            ?? "~/Music/Cadence"
    }

    private func navigate(to destination: NavigationDestination) {
        if let openDestination {
            openDestination(destination)
        } else {
            model.requestNavigationDestination(destination)
        }
    }
}
