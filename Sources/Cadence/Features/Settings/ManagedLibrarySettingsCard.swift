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
            title: "Managed Library",
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
            "Delete Entire Library?",
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button("Delete Library", role: .destructive) {
                Task { await model.deleteEntireManagedLibrary() }
            }
            .cadenceActionTint(.destructive)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Cadence will stop playback, replace the current library with an empty one, "
                    + "and move the original Cadence folder to Trash."
            )
        }
        .alert(
            "Library Reset",
            isPresented: Binding(
                get: { model.libraryResetNotice != nil },
                set: {
                    if !$0 {
                        model.dismissLibraryResetNotice()
                    }
                }
            )
        ) {
            Button("Dismiss", role: .cancel) {
                model.dismissLibraryResetNotice()
            }
        } message: {
            Text(
                model.libraryResetNotice
                    ?? "Cadence finished the library reset operation."
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
        LabeledContent("Available Tracks") {
            Text(store.catalogCounts.liveTrackCount.formatted())
        }
        LabeledContent("Tracks in Trash") {
            Text(store.catalogCounts.trashedTrackCount.formatted())
        }
        LabeledContent("Library Size") {
            Text(libraryStorageSize)
                .monospacedDigit()
        }
    }

    private var libraryActions: some View {
        HStack {
            Button("Import Music…", systemImage: "folder.badge.plus") {
                navigate(to: .importMusic)
            }
            Button("Open Trash", systemImage: "trash") {
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
                "Delete Entire Library…",
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

            Text("The original folder is moved to the system Trash and can be recovered there.")
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
