import QenTerraFoundation
import SwiftUI

enum TrackPickerTarget: Hashable {
    case playlist(LibraryPlaylistProjection)
    case tag(LibraryTagProjection)

    var subtitle: String {
        switch self {
        case let .playlist(playlist): playlist.name
        case let .tag(tag): tag.displayPath
        }
    }

    var noun: String {
        switch self {
        case .playlist: String(localized: "playlist")
        case .tag: String(localized: "tag")
        }
    }
}

enum TrackPickerLayoutMetrics {
    static let minimumWidth = CGFloat(760)
    static let idealWidth = CGFloat(880)
    static let minimumHeight = CGFloat(560)
}

struct TagTrackPickerSheet: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let target: TrackPickerTarget

    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [LibraryTrackProjection] = []
    @State private var nextCursor: LibraryPageCursor?
    @State private var directlyAssignedIDs: Set<UUID> = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var searchQuery = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isLoadingNext = false
    @State private var loadGeneration = 0
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
        .frame(
            minWidth: TrackPickerLayoutMetrics.minimumWidth,
            idealWidth: TrackPickerLayoutMetrics.idealWidth,
            minHeight: TrackPickerLayoutMetrics.minimumHeight
        )
        .background(CadenceTheme.opaqueSurface)
        .task(id: SearchNormalizer.normalize(searchQuery)) {
            await loadFirstPage()
        }
        .onChange(of: store.artworkPublication?.generation) {
            applyArtworkPublication()
        }
        .alert(
            "Couldn’t Add Tracks",
            isPresented: errorPresented
        ) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(
                errorMessage
                    ?? "Cadence could not update this \(target.noun). Your library was not changed."
            )
        }
    }
}

private extension TagTrackPickerSheet {
    var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Tracks")
                    .font(.title2.bold())
                Text(target.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 20)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Tracks", text: $searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(width: 280, height: 34)
            .background(CadenceTheme.subduedFill)
            .clipShape(
                RoundedRectangle(
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
        }
        .padding(.horizontal, 24)
        .frame(height: 84)
        .background(CadenceTheme.secondarySurface)
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
                description: Text("Import music before adding tracks.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleTracks.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !alreadyAssignedTracks.isEmpty {
                        Text("Already Added")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        ForEach(alreadyAssignedTracks) { track in
                            trackRow(track, isAlreadyAssigned: true)
                        }
                    }

                    Text("Library")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, alreadyAssignedTracks.isEmpty ? 8 : 18)
                    ForEach(availableTracks) { track in
                        trackRow(track, isAlreadyAssigned: false)
                            .task {
                                guard track.id == availableTracks.last?.id else {
                                    return
                                }
                                await loadNextPage()
                            }
                    }

                    if isLoadingNext {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .contentMargins(.vertical, 12, for: .scrollContent)
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
            .cadenceActionTint(.confirmation)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedIDs.isEmpty || isSaving)
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
        .background(CadenceTheme.secondarySurface)
    }

    func trackRow(
        _ track: LibraryTrackProjection,
        isAlreadyAssigned: Bool
    ) -> some View {
        Button {
            guard !isAlreadyAssigned else { return }
            if selectedIDs.contains(track.id) {
                selectedIDs.remove(track.id)
            } else {
                selectedIDs.insert(track.id)
            }
        } label: {
            HStack(spacing: 11) {
                ProductionArtworkView(
                    model: model,
                    artworkID: track.artworkID,
                    title: track.title,
                    placeholder: .track,
                    cornerRadius: CadenceTheme.radiusControl
                )
                .frame(width: 38, height: 38)

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
                    Text("Added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(
                    systemName: isAlreadyAssigned || selectedIDs.contains(track.id)
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.title3)
                .foregroundStyle(
                    isAlreadyAssigned
                        ? Color.secondary
                        : selectedIDs.contains(track.id)
                        ? Color.accentColor
                        : Color.secondary.opacity(0.6)
                )
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(
                selectedIDs.contains(track.id)
                    ? CadenceTheme.selectionFill
                    : CadenceTheme.subduedFill.opacity(0.45),
                in: RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusControl,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyAssigned || isSaving)
    }

    var visibleTracks: [LibraryTrackProjection] {
        tracks
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

    func loadFirstPage() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }
        do {
            async let loadedPage = store.tracksForTagPicker(
                search: searchQuery
            )
            async let loadedAssigned = assignedTrackIDs()
            let (page, assignedIDs) = try await (
                loadedPage,
                loadedAssigned
            )
            guard generation == loadGeneration else {
                return
            }
            tracks = page.items
            nextCursor = page.nextCursor
            directlyAssignedIDs = assignedIDs
            applyArtworkPublication()
        } catch {
            guard generation == loadGeneration else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func loadNextPage() async {
        guard
            !isLoadingNext,
            let nextCursor
        else {
            return
        }
        isLoadingNext = true
        let generation = loadGeneration
        defer {
            if generation == loadGeneration {
                isLoadingNext = false
            }
        }
        do {
            let page = try await store.tracksForTagPicker(
                after: nextCursor,
                search: searchQuery
            )
            guard generation == loadGeneration else {
                return
            }
            let existingIDs = Set(tracks.map(\.id))
            tracks.append(
                contentsOf: page.items.filter {
                    !existingIDs.contains($0.id)
                }
            )
            self.nextCursor = page.nextCursor
            applyArtworkPublication()
        } catch {
            guard generation == loadGeneration else {
                return
            }
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
                switch target {
                case let .tag(tag):
                    try await store.assignTag(tag.id, trackIDs: trackIDs)
                case let .playlist(playlist):
                    try await store.addToPlaylistConfirmingPersistence(
                        playlistID: playlist.id,
                        trackIDs: trackIDs
                    )
                }
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func assignedTrackIDs() async throws -> Set<UUID> {
        switch target {
        case let .tag(tag):
            try await store.directlyAssignedTrackIDs(tagID: tag.id)
        case let .playlist(playlist):
            Set(
                store.selectedPlaylistTrackSource(for: playlist.id)?
                    .tracks.map(\.id) ?? []
            )
        }
    }

    func applyArtworkPublication() {
        guard
            let publication = store.artworkPublication,
            publication.epoch == store.libraryEpoch
        else {
            return
        }
        publication.mergeTracks(into: &tracks)
    }
}
