import SwiftUI

struct ProductionLibraryView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore

    @State var selectedArtistID: UUID?
    @State var selectedAlbumID: UUID?
    @State var selectedTrackID: UUID?

    var body: some View {
        Group {
            switch store.availability {
            case let .failed(failure):
                ContentUnavailableView(
                    "Couldn’t Load Library",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        ProductErrorMessage(
                            detail: failure.message,
                            preservedState: String(localized: "Your library is unchanged."),
                            recoveryAction: String(localized: "Try again.")
                        ).text
                    )
                )
                .overlay(alignment: .bottom) {
                    Button("Try Again") {
                        Task {
                            await store.loadInitialLibrary()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 32)
                }
            case .loading where store.artists.isEmpty:
                ProgressView("Loading Library")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty, .ready, .loading:
                if store.tracks.isEmpty {
                    EmptyLibraryView(
                        title: "Your Library Is Empty",
                        description: "Import a folder to start building your Cadence library."
                    ) {
                        model.requestNavigationDestination(.importMusic)
                    }
                } else {
                    columns
                }
            }
        }
        .onChange(of: store.artists, initial: true) {
            repairArtistSelection()
        }
        .task(id: selectedArtistID) {
            await store.browseAlbums(artistID: selectedArtistID)
            guard selectedArtistID == store.browserArtistID else {
                return
            }
            repairAlbumSelection()
        }
        .onChange(of: store.browserAlbums) {
            repairAlbumSelection()
        }
        .task(id: selectedAlbumID) {
            await store.browseTracks(albumID: selectedAlbumID)
            guard selectedAlbumID == store.browserAlbumID else {
                return
            }
            repairTrackSelection()
        }
        .onChange(of: store.browserTracks) {
            repairTrackSelection()
        }
    }

    private var columns: some View {
        GeometryReader { geometry in
            let widths = LibraryColumnWidths(totalWidth: geometry.size.width)

            HStack(spacing: 0) {
                projectionColumn(
                    title: "Artists",
                    count: store.artists.count
                ) {
                    ForEach(store.artists) { artist in
                        artistRow(artist)
                    }
                }
                .frame(width: widths.artists)
                .clipped()

                productionDivider

                projectionColumn(
                    title: "Albums",
                    count: visibleAlbums.count
                ) {
                    ForEach(visibleAlbums) { album in
                        albumRow(album)
                    }
                }
                .frame(width: widths.albums)
                .clipped()

                productionDivider

                VStack(spacing: 0) {
                    LibraryColumnHeader(
                        title: "Tracks",
                        detail: visibleTracks.count.formatted()
                    )

                    trackColumnContent
                }
                .frame(width: widths.tracks)
                .clipped()
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
            .clipped()
        }
    }

    var visibleAlbums: [LibraryAlbumProjection] {
        guard selectedArtistID == store.browserArtistID else {
            return []
        }
        return store.browserAlbums
    }

    var visibleTracks: [LibraryTrackProjection] {
        guard selectedAlbumID == store.browserAlbumID else {
            return []
        }
        return store.browserTracks
    }

    @ViewBuilder
    private var trackColumnContent: some View {
        switch LibraryBrowserColumnPresentation.resolve(
            hasSelection: selectedAlbumID != nil,
            loadState: store.browserTracksState,
            itemCount: visibleTracks.count
        ) {
        case .selectionRequired:
            ContentUnavailableView(
                "Select an Album",
                systemImage: "rectangle.stack",
                description: Text("Choose an album to see its tracks.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ProgressView("Loading Tracks")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView(
                "No Tracks",
                systemImage: "music.note.list",
                description: Text("This album has no available tracks.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn’t Load Tracks", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task {
                        await store.browseTracks(
                            albumID: selectedAlbumID,
                            sort: store.browserTrackSort
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .content:
            ProductionTrackTable(
                model: model,
                tracks: visibleTracks,
                contentVersion: store.browserTracksVersion,
                context: selectedAlbumID.map(TrackTableContext.album)
                    ?? .library,
                showsHeader: false,
                compact: true,
                onReachEnd: {
                    await store.loadNextBrowserTracks()
                },
                repositorySortAction: { sort in
                    await store.sortBrowserTracks(sort)
                },
                refreshAction: {
                    await store.refresh(.library)
                }
            )
            .padding(.bottom, 16)
        }
    }

    private func projectionColumn(
        title: String,
        count: Int,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            LibraryColumnHeader(
                title: title,
                detail: count.formatted()
            )

            ScrollView(.vertical) {
                LazyVStack(spacing: 4) {
                    content()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
            .refreshable {
                await store.refresh(.library)
            }
        }
    }
}

private extension ProductionLibraryView {
    func artistRow(
        _ artist: LibraryArtistProjection
    ) -> some View {
        Button {
            if selectedArtistID == artist.id {
                model.requestOpenProductionArtistContextually(id: artist.id)
            } else {
                selectArtist(artist)
            }
        } label: {
            artistRowLabel(artist)
        }
        .buttonStyle(CadenceRowButtonStyle())
        .contextMenu {
            artistActions(artist)
        }
        .task {
            if artist.id == store.artists.last?.id {
                await store.loadNextArtists()
            }
        }
    }

    func albumRow(
        _ album: LibraryAlbumProjection
    ) -> some View {
        Button {
            if selectedAlbumID == album.id {
                model.requestOpenProductionAlbumContextually(id: album.id)
            } else {
                selectedAlbumID = album.id
                selectedTrackID = nil
            }
        } label: {
            albumRowLabel(album)
        }
        .buttonStyle(CadenceRowButtonStyle())
        .contextMenu {
            albumActions(album)
        }
        .task {
            if album.id == visibleAlbums.last?.id {
                await store.loadNextBrowserAlbums()
            }
        }
    }

    func artistRowLabel(
        _ artist: LibraryArtistProjection
    ) -> some View {
        HStack(spacing: 12) {
            projectionArtwork(
                artworkID: artist.customArtworkID,
                title: artist.name,
                placeholder: .artist,
                isCircular: true
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(
                    "\(artist.albumCount) albums · "
                        + "\(artist.trackCount) tracks"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BrowserRowSurface(
                isSelected: selectedArtistID == artist.id,
                isHovered: false,
                isFocused: false
            )
        }
        .contentShape(Rectangle())
    }

    func albumRowLabel(
        _ album: LibraryAlbumProjection
    ) -> some View {
        HStack(spacing: 14) {
            projectionArtwork(
                artworkID: album.customArtworkID,
                title: album.title,
                placeholder: .album
            )
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text(album.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(album.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(album.trackCount) tracks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .frame(height: 96)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BrowserRowSurface(
                isSelected: selectedAlbumID == album.id,
                isHovered: false,
                isFocused: false
            )
        }
        .contentShape(Rectangle())
    }

    func selectArtist(_ artist: LibraryArtistProjection) {
        selectedArtistID = artist.id
        selectedAlbumID = nil
        selectedTrackID = nil
    }

    var productionDivider: some View {
        Rectangle()
            .fill(CadenceTheme.separator)
            .frame(width: 1)
    }

    func artworkMenu(
        _ target: ArtworkTarget,
        label: String
    ) -> some View {
        ArtworkMenuItems(model: model, target: target, label: label)
    }

    @ViewBuilder
    func artistActions(
        _ artist: LibraryArtistProjection
    ) -> some View {
        AddArtistToPlaylistMenuItems(
            store: store,
            artistID: artist.id
        )
        artworkMenu(.managedArtist(artist.id), label: "Artist Image")
        Divider()
        Button(
            "Move Artist to Trash…",
            systemImage: "trash",
            role: .destructive
        ) {
            model.requestLibraryDeletion(
                kind: .artist,
                id: artist.id,
                title: artist.name
            )
        }
    }

    @ViewBuilder
    func albumActions(
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
        artworkMenu(.managedAlbum(album.id), label: "Album Artwork")
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
}
