import SwiftUI

struct TagTrackPickerSheet: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let tag: LibraryTagProjection

    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [LibraryTrackProjection] = []
    @State private var directlyAssignedIDs: Set<UUID> = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var searchQuery = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            content

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            footer
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520)
        .background(CadenceTheme.contentBackground)
        .searchable(
            text: $searchQuery,
            placement: .toolbar,
            prompt: "Search Tracks"
        )
        .task {
            await load()
        }
        .alert(
            "Couldn’t Add Tracks",
            isPresented: errorPresented
        ) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }
}

private extension TagTrackPickerSheet {
    var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Add Tracks")
                .font(.title2.bold())
            Text(tag.displayPath)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .frame(height: 76)
    }

    @ViewBuilder
    var content: some View {
        if isLoading {
            ProgressView("Loading Library")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tracks.isEmpty {
            ContentUnavailableView(
                "No Tracks Yet",
                systemImage: "music.note",
                description: Text("Import music before assigning this tag.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleTracks.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selectedIDs) {
                if !alreadyAssignedTracks.isEmpty {
                    Section("Already Added") {
                        ForEach(alreadyAssignedTracks) { track in
                            trackLabel(track, isAlreadyAssigned: true)
                        }
                    }
                }

                Section("Library") {
                    ForEach(availableTracks) { track in
                        trackLabel(track, isAlreadyAssigned: false)
                            .tag(track.id)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    var footer: some View {
        HStack {
            Button("Select All") {
                selectedIDs = Set(availableTracks.map(\.id))
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(availableTracks.isEmpty || isSaving)

            Text(selectionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isSaving)

            Button("Add") {
                addSelectedTracks()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedIDs.isEmpty || isSaving)
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
    }

    func trackLabel(
        _ track: LibraryTrackProjection,
        isAlreadyAssigned: Bool
    ) -> some View {
        HStack(spacing: 11) {
            ProductionArtworkView(
                model: model,
                artworkID: track.artworkID,
                title: track.title,
                placeholder: .track,
                cornerRadius: 5
            )
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .lineLimit(1)
                Text("\(track.artist) · \(track.album)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isAlreadyAssigned {
                Label("Added", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    var visibleTracks: [LibraryTrackProjection] {
        guard !SearchNormalizer.normalize(searchQuery).isEmpty else {
            return tracks
        }
        let query = SearchNormalizer.normalize(searchQuery)
        return tracks.filter {
            SearchNormalizer.normalize(
                "\($0.title) \($0.artist) \($0.album)"
            ).contains(query)
        }
    }

    var alreadyAssignedTracks: [LibraryTrackProjection] {
        visibleTracks.filter { directlyAssignedIDs.contains($0.id) }
    }

    var availableTracks: [LibraryTrackProjection] {
        visibleTracks.filter { !directlyAssignedIDs.contains($0.id) }
    }

    var selectionSummary: String {
        let count = selectedIDs.count
        return count == 1 ? "1 track selected" : "\(count) tracks selected"
    }

    var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
        }
        do {
            async let loadedTracks = store.tracksForTagPicker()
            async let loadedAssigned = store.directlyAssignedTrackIDs(
                tagID: tag.id
            )
            tracks = try await loadedTracks
            directlyAssignedIDs = try await loadedAssigned
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addSelectedTracks() {
        let trackIDs = Array(selectedIDs)
        guard !trackIDs.isEmpty else {
            return
        }
        isSaving = true
        Task {
            do {
                try await store.assignTag(tag.id, trackIDs: trackIDs)
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
