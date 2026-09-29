import QenTerraComponents
import SwiftUI

struct ProductionAlbumDetailView: View {
    @Environment(\.albumDetailReadinessObserver) private var readinessObserver
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let albumID: UUID

    @State private var album: LibraryAlbumProjection?
    @State private var tracks: [LibraryTrackProjection] = []
    @State private var tracksClock = TrackTableContentClock()
    @State private var albumTags: [LibraryTagProjection] = []
    @State private var isLoading = true
    @State private var loadFailure: String?
    @State private var loadGeneration = 0
    @State private var isEditorPresented = false

    var body: some View {
        Group {
            if let album {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        backButton
                        refreshFailureNotice
                        header(album)
                        ProductionTrackList(
                            model: model,
                            tracks: tracks,
                            contentVersion: tracksClock.version,
                            context: .album(albumID)
                        )
                        .frame(
                            height: min(
                                max(CGFloat(tracks.count * 58 + 38), 240),
                                520
                            )
                        )
                    }
                    .padding(28)
                }
            } else if isLoading {
                ProgressView("Loading Album")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadFailure {
                ContentUnavailableView {
                    Label(
                        "Couldn’t Load Album",
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(loadFailure)
                } actions: {
                    Button("Retry") {
                        loadGeneration &+= 1
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Album Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This album is no longer in the library.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(CadenceTheme.contentBackground)
        .sheet(isPresented: $isEditorPresented) {
            if let album {
                CatalogEntityEditorSheet(
                    model: model,
                    title: "Edit Album",
                    fieldLabel: "Album Name",
                    initialValue: album.title,
                    artworkTarget: .managedAlbum(album.id),
                    artworkLabel: "Album Artwork"
                ) { title in
                    guard let renamed = await model.renameProductionAlbum(
                        id: album.id,
                        title: title
                    ) else {
                        return false
                    }
                    self.album = renamed
                    return true
                }
            }
        }
        .task(
            id: "\(albumID.uuidString)-\(store.tagRevision)-\(loadGeneration)"
        ) {
            await loadContent()
        }
        .onChange(of: store.artworkPublication?.generation) {
            applyArtworkPublication()
        }
    }

    private func albumFavoriteButton(
        _ album: LibraryAlbumProjection
    ) -> some View {
        FavoriteButton(
            itemID: album.id,
            isFavorite: album.isFavorite,
            itemName: album.title,
            controlSize: 34
        ) { requestedValue in
            guard let updated = await model.setProductionAlbumFavorite(
                album,
                isFavorite: requestedValue
            ) else {
                return false
            }
            self.album = updated
            return true
        }
        .imageScale(.large)
    }

    private func playbackActions(
        _ album: LibraryAlbumProjection
    ) -> some View {
        HStack(spacing: 10) {
            Button("Play", systemImage: "play.fill") {
                model.playProductionAlbum(album, tracks: tracks)
            }
            .buttonStyle(.borderedProminent)
            .disabled(tracks.isEmpty)

            Button("Shuffle", systemImage: "shuffle") {
                model.playProductionAlbum(
                    album,
                    tracks: tracks,
                    shuffled: true
                )
            }
            .buttonStyle(.bordered)
            .disabled(tracks.isEmpty)
        }
    }
}

private extension ProductionAlbumDetailView {
    private var backButton: some View {
        Button {
            model.requestContextualBack()
        } label: {
            Label("Back to \(model.contextualBackTitle)", systemImage: "chevron.left")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func header(
        _ album: LibraryAlbumProjection
    ) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            ProductionArtworkView(
                model: model,
                artworkID: album.customArtworkID,
                title: album.title,
                placeholder: .album,
                variant: .original,
                cornerRadius: CadenceTheme.radiusPanel
            )
            .frame(width: 210, height: 210)

            VStack(alignment: .leading, spacing: 8) {
                VStack(
                    alignment: .leading,
                    spacing: CatalogDetailHeaderMetrics.eyebrowTitleSpacing
                ) {
                    CatalogDetailEyebrow("ALBUM")
                    albumTitle(album)
                }
                Button {
                    guard let artistID = album.artistID else {
                        return
                    }
                    model.requestOpenProductionArtistContextually(id: artistID)
                } label: {
                    Text(album.artist)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(album.artistID == nil)
                Text(albumMetadata(album))
                    .font(.callout)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 10) {
                    playbackActions(album)
                    albumFavoriteButton(album)
                    Spacer(minLength: 16)
                    editButton
                    actionsMenu(album)
                }
                .padding(.top, 4)
                albumTagChips
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var editButton: some View {
        Button("Edit", systemImage: "pencil") {
            isEditorPresented = true
        }
        .buttonStyle(.bordered)
    }

    private func actionsMenu(
        _ album: LibraryAlbumProjection
    ) -> some View {
        Menu {
            albumActions(album)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .help("Album Actions")
    }

    @ViewBuilder
    private var albumTagChips: some View {
        if !albumTags.isEmpty {
            DesignFlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                ForEach(albumTags) { tag in
                    Button {
                        model.requestOpenProductionTagContextually(
                            id: tag.id
                        )
                    } label: {
                        Label(tag.displayPath, systemImage: "tag")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(
                                CadenceTheme.subduedFill,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func albumActions(
        _ album: LibraryAlbumProjection
    ) -> some View {
        FavoriteContextMenuItem(isFavorite: album.isFavorite) {
            Task {
                guard let updated = await model.setProductionAlbumFavorite(
                    album,
                    isFavorite: !album.isFavorite
                ) else {
                    return
                }
                self.album = updated
            }
        }
        Divider()
        QuickAlbumTagMenuItems(
            store: store,
            albumID: album.id
        )
        AddAlbumToPlaylistMenuItems(
            store: store,
            albumID: album.id
        )
        Divider()
        Button(
            "Move Album to Trash…",
            systemImage: "trash",
            role: .destructive
        ) {
            model.requestLibraryDeletion(
                kind: .album,
                id: album.id,
                title: album.title
            )
        }
    }

    @ViewBuilder
    var refreshFailureNotice: some View {
        if let loadFailure {
            HStack {
                Label(loadFailure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry") {
                    loadGeneration &+= 1
                }
            }
        }
    }

    func loadContent() async {
        isLoading = true
        do {
            async let loadedAlbum = store.album(id: albumID)
            async let loadedTracks = store.tracks(albumID: albumID)
            async let loadedTags = store.tags(albumID: albumID)
            let result = try await (
                album: loadedAlbum,
                tracks: loadedTracks,
                tags: loadedTags
            )
            album = result.album
            if tracks != result.tracks {
                tracks = result.tracks
                tracksClock.advance()
            }
            albumTags = result.tags
            applyArtworkPublication()
            loadFailure = nil
        } catch {
            loadFailure = error.localizedDescription
        }
        isLoading = false
        if loadFailure == nil {
            readinessObserver?.notify(albumID)
        }
    }

    func albumTitle(_ album: LibraryAlbumProjection) -> some View {
        Text(album.title)
            .font(.largeTitle.bold())
    }

    func albumMetadata(_ album: LibraryAlbumProjection) -> String {
        var parts = ["\(album.trackCount) tracks"]
        if let year = album.year {
            parts.append(year.formatted(.number.grouping(.never)))
        }
        return parts.joined(separator: " · ")
    }

    func applyArtworkPublication() {
        guard
            let publication = store.artworkPublication,
            publication.epoch == store.libraryEpoch
        else {
            return
        }
        if let replacement = publication.albumsByID[albumID] {
            album = replacement
        }
        if publication.mergeTracks(into: &tracks) {
            tracksClock.advance()
        }
    }
}
