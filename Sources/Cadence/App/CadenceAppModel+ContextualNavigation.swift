import Foundation

extension CadenceAppModel {
    var hasContextualBackNavigation: Bool {
        !contextualNavigationHistory.isEmpty
    }

    var contextualBackTitle: String {
        contextualNavigationHistory.last?.source.sourceTitle
            ?? selectedDestination.title
    }

    func requestOpenArtistContextually(_ artist: ArtistPreview) {
        requestContextualNavigation(.artist(artist.id))
    }

    func requestOpenArtistContextually(
        id: ArtistPreview.ID
    ) {
        requestContextualNavigation(.artist(id))
    }

    func requestOpenAlbumContextually(_ album: AlbumPreview) {
        requestContextualNavigation(.album(album.id))
    }

    func requestOpenAlbumContextually(id: AlbumPreview.ID) {
        requestContextualNavigation(.album(id))
    }

    func requestOpenTagContextually(_ tag: TagPreview) {
        requestContextualNavigation(.tag(tag.id))
    }

    func requestOpenProductionArtistContextually(id: UUID) {
        requestContextualNavigation(.productionArtist(id))
    }

    func requestOpenProductionAlbumContextually(id: UUID) {
        requestContextualNavigation(.productionAlbum(id))
    }

    func requestOpenProductionTagContextually(id: UUID) {
        requestContextualNavigation(.productionTag(id))
    }

    func openProductionTagEditor(trackID: UUID) {
        requestContextualNavigation(.productionTagEditor(trackID))
    }

    func requestContextualBack() {
        guard let entry = contextualNavigationHistory.popLast() else {
            return
        }
        restoreContextualSnapshot(entry.source)
    }

    func performContextualNavigation(_ route: ContextualMediaRoute) {
        guard
            playbackWorkspace != .lyricsEditor,
            contextualRouteExists(route)
        else {
            return
        }

        let entry = ContextualNavigationEntry(
            target: route,
            source: makeContextualSnapshot()
        )
        contextualNavigationHistory.append(entry)
        if contextualNavigationHistory.count > 24 {
            contextualNavigationHistory.removeFirst(
                contextualNavigationHistory.count - 24
            )
        }

        playbackWorkspace = .hidden
        applyContextualRoute(route)
    }

    private func requestContextualNavigation(
        _ route: ContextualMediaRoute
    ) {
        guard contextualRouteExists(route) else {
            return
        }
        let requiresSmartCollectionConfirmation =
            selectedDestination == .smartCollections
                && smartCollectionsPresentationMode == .editing
                && isSmartCollectionDraftDirty
        if requiresSmartCollectionConfirmation {
            pendingSmartCollectionTransition = .contextualRoute(route)
            return
        }
        performContextualNavigation(route)
    }

    private func applyContextualRoute(_ route: ContextualMediaRoute) {
        librarySession.store.clearCatalogSearch()

        switch route {
        case let .artist(artistID):
            guard let artist = artists.first(where: { $0.id == artistID }) else {
                return
            }
            requestOpenArtist(artist, origin: .overview)
            selectedDestination = .artists
        case let .album(albumID):
            guard let album = albums.first(where: { $0.id == albumID }) else {
                return
            }
            requestOpenAlbum(album, origin: .overview)
        case let .tag(tagID):
            guard let tag = tags.first(where: { $0.id == tagID }) else {
                return
            }
            clearTagEditingSelection()
            selectedDestination = .tags
            selectedTagGroupID = tag.groupID
            selectedTagID = tag.id
            tagResultScope = .tracks
            isTagInspectorPresented = false
            isLibraryTagEditingContext = false
        case let .productionArtist(artistID):
            selectedDestination = .artists
            selectedProductionArtistID = artistID
            selectedProductionAlbumID = nil
            selectedProductionTagID = nil
        case let .productionAlbum(albumID):
            selectedDestination = .albums
            selectedProductionAlbumID = albumID
            selectedProductionArtistID = nil
            selectedProductionTagID = nil
        case let .productionTag(tagID):
            selectedDestination = .tags
            selectedProductionTagID = tagID
            selectedProductionArtistID = nil
            selectedProductionAlbumID = nil
            selectedProductionTagEditingTrackID = nil
        case let .productionTagEditor(trackID):
            selectedDestination = .tags
            selectedProductionTagID = nil
            selectedProductionArtistID = nil
            selectedProductionAlbumID = nil
            selectedProductionTagEditingTrackID = trackID
        }
    }

    private func contextualRouteExists(
        _ route: ContextualMediaRoute
    ) -> Bool {
        switch route {
        case let .artist(id):
            artists.contains { $0.id == id }
        case let .album(id):
            albums.contains { $0.id == id }
        case let .tag(id):
            tags.contains { $0.id == id }
        case .productionArtist, .productionAlbum, .productionTag:
            librarySession.availability != .preview
        case let .productionTagEditor(trackID):
            librarySession.store.tracks.contains { $0.id == trackID }
        }
    }

    private func makeContextualSnapshot() -> ContextualNavigationSnapshot {
        ContextualNavigationSnapshot(
            sourceTitle: currentContextTitle,
            catalogSearchQuery: librarySession.store.catalogSearchQuery,
            selectedDestination: selectedDestination,
            selectedArtistID: selectedArtistID,
            selectedAlbumID: selectedAlbumID,
            selectedTrackID: selectedTrackID,
            currentTrackID: currentTrackID,
            selectedProductionArtistID: selectedProductionArtistID,
            selectedProductionAlbumID: selectedProductionAlbumID,
            selectedProductionTagID: selectedProductionTagID,
            selectedProductionTagEditingTrackID:
            selectedProductionTagEditingTrackID,
            playbackWorkspace: playbackWorkspace,
            selectedNowPlayingPanel: selectedNowPlayingPanel,
            lastNowPlayingPanel: lastNowPlayingPanel,
            albumsPresentation: albumsPresentation,
            allAlbumsSortDescriptor: allAlbumsSortDescriptor,
            albumShelfSortDescriptors: albumShelfSortDescriptors,
            albumSearchQuery: albumSearchQuery,
            albumsFocusedAlbumID: albumsFocusedAlbumID,
            artistsPresentation: artistsPresentation,
            allArtistsSortDescriptor: allArtistsSortDescriptor,
            artistShelfSortDescriptors: artistShelfSortDescriptors,
            artistSearchQuery: artistSearchQuery,
            artistsFocusedArtistID: artistsFocusedArtistID,
            selectedTagGroupID: selectedTagGroupID,
            selectedTagID: selectedTagID,
            tagResultScope: tagResultScope,
            tagEditingSelection: tagEditingSelection,
            isTagInspectorPresented: isTagInspectorPresented,
            isLibraryTagEditingContext: isLibraryTagEditingContext,
            selectedSmartCollectionID: selectedSmartCollectionID,
            smartCollectionsPresentationMode: smartCollectionsPresentationMode,
            smartCollectionDraft: smartCollectionDraft,
            smartCollectionSortDescriptors: smartCollectionSortDescriptors,
            lastValidSmartCollectionResultIDs: lastValidSmartCollectionResultIDs
        )
    }

    private func restoreContextualSnapshot(
        _ snapshot: ContextualNavigationSnapshot
    ) {
        librarySession.store.restoreCatalogSearch(
            snapshot.catalogSearchQuery
        )
        selectedDestination = snapshot.selectedDestination
        selectedArtistID = snapshot.selectedArtistID
        selectedAlbumID = snapshot.selectedAlbumID
        selectedTrackID = snapshot.selectedTrackID
        currentTrackID = snapshot.currentTrackID
        selectedProductionArtistID = snapshot.selectedProductionArtistID
        selectedProductionAlbumID = snapshot.selectedProductionAlbumID
        selectedProductionTagID = snapshot.selectedProductionTagID
        selectedProductionTagEditingTrackID =
            snapshot.selectedProductionTagEditingTrackID

        playbackWorkspace = snapshot.playbackWorkspace
        selectedNowPlayingPanel = snapshot.selectedNowPlayingPanel
        lastNowPlayingPanel = snapshot.lastNowPlayingPanel

        albumsPresentation = snapshot.albumsPresentation
        allAlbumsSortDescriptor = snapshot.allAlbumsSortDescriptor
        albumShelfSortDescriptors = snapshot.albumShelfSortDescriptors
        albumSearchQuery = snapshot.albumSearchQuery
        albumsFocusedAlbumID = snapshot.albumsFocusedAlbumID

        artistsPresentation = snapshot.artistsPresentation
        allArtistsSortDescriptor = snapshot.allArtistsSortDescriptor
        artistShelfSortDescriptors = snapshot.artistShelfSortDescriptors
        artistSearchQuery = snapshot.artistSearchQuery
        artistsFocusedArtistID = snapshot.artistsFocusedArtistID

        selectedTagGroupID = snapshot.selectedTagGroupID
        selectedTagID = snapshot.selectedTagID
        tagResultScope = snapshot.tagResultScope
        tagEditingSelection = snapshot.tagEditingSelection
        isTagInspectorPresented = snapshot.isTagInspectorPresented
        isLibraryTagEditingContext = snapshot.isLibraryTagEditingContext

        selectedSmartCollectionID = snapshot.selectedSmartCollectionID
        smartCollectionsPresentationMode =
            snapshot.smartCollectionsPresentationMode
        smartCollectionDraft = snapshot.smartCollectionDraft
        smartCollectionSortDescriptors =
            snapshot.smartCollectionSortDescriptors
        lastValidSmartCollectionResultIDs =
            snapshot.lastValidSmartCollectionResultIDs

        repairRestoredContext()
    }

    private func repairRestoredContext() {
        let hasSelectedArtist = selectedArtistID.map { id in
            artists.contains { $0.id == id }
        } ?? true
        if !hasSelectedArtist {
            selectedArtistID = artists.first?.id
            artistsPresentation = .overview
        }

        let hasSelectedAlbum = selectedAlbumID.map { id in
            albums.contains { $0.id == id }
        } ?? true
        if !hasSelectedAlbum {
            selectedAlbumID = albums.first?.id
            albumsPresentation = .overview
        }

        let hasSelectedTrack = selectedTrackID.map { id in
            tracks.contains { $0.id == id }
        } ?? true
        if !hasSelectedTrack {
            selectedTrackID = tracks.first?.id
        }

        let hasCurrentTrack = currentTrackID.map { id in
            tracks.contains { $0.id == id }
        } ?? true
        if !hasCurrentTrack {
            currentTrackID = nil
            playbackWorkspace = .hidden
        }

        let hasSelectedTag = selectedTagID.map { id in
            tags.contains { $0.id == id }
        } ?? true
        if !hasSelectedTag {
            selectedTagID = nil
            selectedTagGroupID = .all
        }

        let hasSelectedSmartCollection = selectedSmartCollectionID.map { id in
            smartCollections.contains { $0.id == id }
        } ?? true
        if !hasSelectedSmartCollection {
            selectedSmartCollectionID = smartCollections.first?.id
            smartCollectionsPresentationMode = .listening
            smartCollectionDraft = nil
        }
    }

    private var currentContextTitle: String {
        if playbackWorkspace == .nowPlaying {
            return "Now Playing"
        }
        switch selectedDestination {
        case .albums:
            return librarySession.store.albums.first {
                $0.id == selectedProductionAlbumID
            }?.title ?? presentedAlbum?.title ?? "Albums"
        case .artists:
            return librarySession.store.artists.first {
                $0.id == selectedProductionArtistID
            }?.name ?? presentedArtist?.name ?? "Artists"
        case .tags:
            return librarySession.store.tags.first {
                $0.id == selectedProductionTagID
            }?.displayPath ?? selectedTag?.displayPath ?? "Tags"
        case .smartCollections:
            return selectedSmartCollection?.name ?? "Smart Collections"
        default:
            return selectedDestination.title
        }
    }
}
