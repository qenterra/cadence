import SwiftUI

struct ProductionAlbumDetailView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let albumID: UUID

    @State private var album: LibraryAlbumProjection?
    @State private var tracks: [LibraryTrackProjection] = []
    @State private var albumTags: [LibraryTagProjection] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if let album {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        backButton
                        header(album)
                        CadenceSeparator()
                        ProductionTrackList(model: model, tracks: tracks)
                    }
                    .padding(28)
                }
            } else if isLoading {
                ProgressView("Loading Album")
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
        .task(id: "\(albumID.uuidString)-\(store.tagRevision)") {
            isLoading = true
            async let loadedAlbum = store.album(id: albumID)
            async let loadedTracks = store.tracks(albumID: albumID)
            async let loadedTags = try? store.tags(albumID: albumID)
            album = await loadedAlbum
            tracks = await loadedTracks
            albumTags = await loadedTags ?? []
            isLoading = false
        }
    }

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
                cornerRadius: 16
            )
            .frame(width: 210, height: 210)

            VStack(alignment: .leading, spacing: 8) {
                Text("ALBUM")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(album.title)
                    .font(.largeTitle.bold())
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

                albumTagChips
            }
            Spacer()
            Menu {
                albumActions(album)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .help("Album Actions")
        }
    }

    @ViewBuilder
    private var albumTagChips: some View {
        if !albumTags.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
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
            }
            .scrollIndicators(.hidden)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func albumActions(
        _ album: LibraryAlbumProjection
    ) -> some View {
        QuickAlbumTagMenuItems(
            store: store,
            albumID: album.id
        )
        AddAlbumToPlaylistMenuItems(
            store: store,
            albumID: album.id
        )
        ArtworkMenuItems(
            model: model,
            target: .managedAlbum(album.id),
            label: "Album Artwork"
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

    private func albumMetadata(
        _ album: LibraryAlbumProjection
    ) -> String {
        var parts = ["\(album.trackCount) tracks"]
        if let year = album.year {
            parts.append(year.formatted(.number.grouping(.never)))
        }
        return parts.joined(separator: " · ")
    }
}
