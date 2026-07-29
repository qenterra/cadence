import SwiftUI

struct ProductionTagEditorInspector: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let trackID: UUID

    @State private var assignedStates: [ProductionTrackTagState] = []
    @State private var newTagPath = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.tags) { tag in
                        tagToggle(tag)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("mood/sad or childhood", text: $newTagPath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createTag)
                Button("Add", action: createTag)
                    .disabled(trimmedNewTagPath.isEmpty || isWorking)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CadenceTheme.secondarySurface)
        .task(id: trackID, loadStates)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Tags")
                    .font(.title3.bold())
                Text(trackTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                model.selectedProductionTagEditingTrackID = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close Tag Editor")
            .accessibilityLabel("Close Tag Editor")
        }
    }

    private func tagToggle(
        _ tag: LibraryTagProjection
    ) -> some View {
        let state = assignedStates.first { $0.id == tag.id }
        return Toggle(
            isOn: Binding(
                get: { state != nil },
                set: { assigned in
                    update(tag: tag, assigned: assigned)
                }
            )
        ) {
            HStack {
                Text(tag.displayPath)
                    .lineLimit(1)
                Spacer()
                if state?.source == .inherited {
                    Text("Inherited")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 8)
        .frame(height: 34)
        .disabled(isWorking)
    }

    private var trackTitle: String {
        store.tracks.first { $0.id == trackID }?.title
            ?? model.currentPlaybackTrack?.title
            ?? "Track"
    }

    private var trimmedNewTagPath: String {
        newTagPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func update(
        tag: LibraryTagProjection,
        assigned: Bool
    ) {
        Task { @MainActor in
            isWorking = true
            defer { isWorking = false }
            do {
                try await store.setTag(
                    tag.id,
                    assigned: assigned,
                    trackID: trackID
                )
                await loadStates()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createTag() {
        let path = trimmedNewTagPath
        guard !path.isEmpty else {
            return
        }
        Task { @MainActor in
            isWorking = true
            defer { isWorking = false }
            do {
                _ = try await store.createTagAndAssign(
                    displayPath: path,
                    trackID: trackID
                )
                newTagPath = ""
                await loadStates()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadStates() async {
        do {
            assignedStates = try await store.tagStates(trackID: trackID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
