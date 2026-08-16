import SwiftUI

struct ManagedLibrarySettingsCard: View {
    @Bindable var model: CadenceAppModel
    @State private var libraryStorageSize = "Calculating…"
    @State private var isDeleteConfirmationPresented = false
    @State private var storageOperationMessage: String?
    @State private var isApplyingStoragePolicy = false
    @AppStorage(LibraryStorageMode.defaultsKey)
    private var storageModeRawValue = LibraryStorageMode.optimize.rawValue

    private var store: LibraryStore {
        model.librarySession.store
    }

    var body: some View {
        SettingsCard(
            title: "Managed Library",
            symbol: "externaldrive"
        ) {
            libraryDetails
            storagePolicy
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

    private var storagePolicy: some View {
        VStack(alignment: .leading, spacing: CadenceLayout.controlGap) {
            Picker("Storage", selection: storageModeBinding) {
                ForEach(LibraryStorageMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .disabled(isApplyingStoragePolicy)

            Text(storagePolicyDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if storageMode == .downloadOriginals {
                    Button("Download Now", systemImage: "arrow.down.circle") {
                        applyStoragePolicy()
                    }
                } else {
                    Button("Free Up Space", systemImage: "internaldrive") {
                        evictDownloadedOriginals()
                    }
                }
                if isApplyingStoragePolicy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let storageOperationMessage {
                Text(storageOperationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                model.requestNavigationDestination(.importMusic)
            }
            Button("Open Trash", systemImage: "trash") {
                model.requestNavigationDestination(.trash)
            }
            Button("Move Library…", systemImage: "externaldrive.badge.plus") {
                model.chooseLibraryLocation()
            }
            .disabled(model.isMovingLibrary)
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

    private var storageMode: LibraryStorageMode {
        LibraryStorageMode(rawValue: storageModeRawValue) ?? .optimize
    }

    private var storageModeBinding: Binding<LibraryStorageMode> {
        Binding(
            get: { storageMode },
            set: { mode in
                storageModeRawValue = mode.rawValue
                storageOperationMessage = nil
                if mode == .downloadOriginals {
                    applyStoragePolicy()
                }
            }
        )
    }

    private var storagePolicyDescription: String {
        switch storageMode {
        case .optimize:
            "Originals download when you play them. macOS may remove local iCloud copies when space is needed."
        case .downloadOriginals:
            "Cadence requests local copies of every original while iCloud continues syncing the library."
        }
    }

    private func applyStoragePolicy() {
        guard let location = model.librarySession.location else {
            return
        }
        let policy = LibraryStoragePolicy(mode: storageMode)
        isApplyingStoragePolicy = true
        storageOperationMessage = nil
        Task {
            do {
                try await Task.detached {
                    try LibraryStoragePolicyApplier().apply(
                        policy,
                        to: ManagedLibraryPackage(location: location)
                    )
                }.value
                storageOperationMessage = "Original downloads have been requested."
            } catch {
                storageOperationMessage = error.localizedDescription
            }
            isApplyingStoragePolicy = false
        }
    }

    private func evictDownloadedOriginals() {
        guard let location = model.librarySession.location else {
            return
        }
        isApplyingStoragePolicy = true
        storageOperationMessage = nil
        Task {
            do {
                try await Task.detached {
                    try LibraryStoragePolicyApplier().evictDownloadedOriginals(
                        in: ManagedLibraryPackage(location: location)
                    )
                }.value
                storageOperationMessage = "Downloaded iCloud originals were released."
            } catch {
                storageOperationMessage = error.localizedDescription
            }
            isApplyingStoragePolicy = false
        }
    }
}
