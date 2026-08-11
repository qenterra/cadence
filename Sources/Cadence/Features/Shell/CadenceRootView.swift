import SwiftUI

struct CadenceRootView: View {
    @Bindable var model: CadenceAppModel
    @State private var isSearchPresented = false
    @State private var cadenceModeSession: CadenceModeSession

    init(
        model: CadenceAppModel,
        cadenceModeSession: CadenceModeSession = CadenceModeSession()
    ) {
        self.model = model
        _cadenceModeSession = State(initialValue: cadenceModeSession)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 0) {
                    NavigationRail(
                        selection: navigationSelection,
                        suppressesSelection: model.isPlaybackWorkspacePresented
                    )
                    Rectangle()
                        .fill(CadenceTheme.separator)
                        .frame(width: 1)
                    workspaceContent
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )

                if model.isImportDropTargeted {
                    ImportMusicDropOverlay()
                        .transition(.opacity)
                }
            }
            .dropDestination(
                for: URL.self
            ) { urls, _ in
                guard !urls.isEmpty else {
                    return false
                }
                model.acceptImportDrop(urls: urls)
                return true
            } isTargeted: { isTargeted in
                model.setImportDropTargeted(isTargeted)
            }

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
            PlayerBar(model: model)
        }
        .background(CadenceTheme.contentBackground)
        .overlay(alignment: .topLeading) {
            CadenceModeInputCapture(
                model: model,
                session: cadenceModeSession
            )
            .frame(width: 0, height: 0)
        }
        .toolbarBackground(
            CadenceTheme.opaqueSurface,
            for: .windowToolbar
        )
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .modifier(
            CadenceSearchModifier(
                isEnabled: model.playbackWorkspace == .hidden
                    && supportsSearch,
                text: activeSearchBinding,
                isPresented: $isSearchPresented,
                prompt: searchHelp
            )
        )
        .lyricsDraftTransitionAlert(model: model)
        .artworkManagement(model: model)
        .confirmationDialog(
            "Move to Trash?",
            isPresented: libraryDeletionPresented,
            presenting: model.pendingLibraryDeletion
        ) { deletion in
            Button("Move to Trash", role: .destructive) {
                Task {
                    await model.confirmLibraryDeletion(deletion)
                }
            }
            Button("Cancel", role: .cancel) {
                model.cancelLibraryDeletion()
            }
        } message: { deletion in
            Text(
                "“\(deletion.title)” will be removed from the library. "
                    + "Its managed files remain in Trash until it is emptied."
            )
        }
        .alert(
            "Library Operation Failed",
            isPresented: libraryOperationErrorPresented
        ) {
            Button("OK") {
                model.dismissLibraryOperationError()
            }
        } message: {
            Text(model.libraryOperationError ?? "Unknown error")
        }
        .alert(
            model.librarySession.store.operationFailure?.title
                ?? "Library Operation Failed",
            isPresented: storeOperationFailurePresented
        ) {
            Button("Retry") {
                Task {
                    await model.librarySession.store.retryOperationFailure()
                }
            }
            Button("Dismiss") {
                model.librarySession.store.dismissOperationFailure()
            }
        } message: {
            Text(
                model.librarySession.store.operationFailure?.message
                    ?? "Unknown error"
            )
        }
        .task {
            model.activateSystemMediaSession()
            await model.recoverManagedLibraryIfNeeded()
            await model.repairImportedMetadataIfNeeded()
            let needsInitialLoad = model.librarySession.availability == .ready
                && model.librarySession.store.tracks.isEmpty
            if needsInitialLoad {
                await model.librarySession.store.loadInitialLibrary()
            }
            await model.loadPersistedSmartCollections()
            await model.librarySession.store.loadPlaylists()
        }
        .task(id: model.currentPlaybackTrack?.id) {
            guard let trackID = model.currentPlaybackTrack?.id else {
                return
            }
            await model.librarySession.store.recordRecentlyPlayed(
                trackID: trackID
            )
        }
        .onDisappear {
            cadenceModeSession.deactivate()
            model.shutdownPlayback()
        }
        .onChange(of: model.selectedDestination) {
            dismissSearch()
        }
        .onKeyPress(.escape, phases: .down) { _ in
            guard isSearchPresented || !activeSearchQuery.isEmpty else {
                return .ignored
            }
            dismissSearch()
            return .handled
        }
        .onKeyPress(.space, phases: .down) { _ in
            commandResult(.togglePlayback)
        }
        .onKeyPress(.leftArrow, phases: .down) { keyPress in
            commandResult(
                .previousTrack,
                keyPress: keyPress,
                requiredModifiers: .command
            )
        }
        .onKeyPress(.rightArrow, phases: .down) { keyPress in
            commandResult(
                .nextTrack,
                keyPress: keyPress,
                requiredModifiers: .command
            )
        }
        .onKeyPress(.upArrow, phases: .down) { keyPress in
            commandResult(
                .volumeUp,
                keyPress: keyPress,
                requiredModifiers: .command
            )
        }
        .onKeyPress(.downArrow, phases: .down) { keyPress in
            commandResult(
                .volumeDown,
                keyPress: keyPress,
                requiredModifiers: .command
            )
        }
    }
}

private extension CadenceRootView {
    private func commandResult(
        _ command: AppCommand,
        keyPress: KeyPress? = nil,
        requiredModifiers: EventModifiers = []
    ) -> KeyPress.Result {
        if let keyPress,
           keyPress.modifiers != requiredModifiers {
            return .ignored
        }
        return AppCommandRouter(model: model).handle(
            command,
            focus: .none
        ) ? .handled : .ignored
    }

    private var navigationSelection: Binding<NavigationDestination> {
        Binding(
            get: { model.selectedDestination },
            set: model.requestNavigationDestination
        )
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch model.playbackWorkspace {
        case .nowPlaying:
            NowPlayingView(
                model: model,
                cadenceModeSession: cadenceModeSession
            )
        case .lyricsEditor:
            LyricsEditorView(model: model)
        case .lyricsSearch:
            if let target = model.lyricsSearchTarget {
                LyricsSearchPreviewView(
                    model: model,
                    target: target
                )
            } else {
                destinationContent
            }
        case .hidden:
            destinationContent
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        if model.librarySession.availability == .recovering {
            ProgressView("Opening Cadence.library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case let .failed(failure) = model.librarySession.availability {
            LibraryUnavailableView(failure: failure) {
                Task {
                    await model.retryManagedLibrary()
                }
            } locate: {
                model.locateUnavailableLibrary()
            }
        } else if shouldPresentProductionSearch {
            ProductionSearchResultsView(
                model: model,
                store: model.librarySession.store
            )
        } else {
            switch model.selectedDestination {
            case .home:
                ProductionHomeView(
                    model: model,
                    store: model.librarySession.store
                )
            case .library:
                LibraryView(model: model)
            case .allTracks:
                AllTracksView(
                    model: model,
                    store: model.librarySession.store
                )
            case .albums:
                AlbumsView(model: model)
            case .artists:
                ArtistsView(model: model)
            case .favorites:
                LibraryFavoritesView(
                    model: model,
                    store: model.librarySession.store
                )
            case .tags:
                TagsView(model: model)
            case .smartCollections:
                SmartCollectionsView(model: model)
            case .playlists:
                PlaylistsView(
                    model: model,
                    store: model.librarySession.store
                )
            case .importMusic:
                ImportMusicView(model: model)
            case .trash:
                ProductionTrashView(model: model)
            }
        }
    }

    private var supportsSearch: Bool {
        switch model.selectedDestination {
        case .home, .library, .allTracks, .albums, .artists, .favorites, .tags,
             .smartCollections, .playlists:
            true
        case .importMusic, .trash:
            false
        }
    }

    private var activeSearchQuery: String {
        model.librarySession.store.catalogSearchQuery
    }

    private var searchHelp: String {
        "Search Library"
    }

    private var shouldPresentProductionSearch: Bool {
        supportsSearch
            && (isSearchPresented
                || !SearchNormalizer.normalize(activeSearchQuery).isEmpty)
    }

    private var productionSearchBinding: Binding<String> {
        Binding(
            get: {
                model.librarySession.store.catalogSearchQuery
            },
            set: { query in
                Task {
                    await model.librarySession.store.searchCatalog(query)
                }
            }
        )
    }

    private var activeSearchBinding: Binding<String> {
        productionSearchBinding
    }

    private func dismissSearch() {
        isSearchPresented = false
        model.librarySession.store.clearCatalogSearch()
    }

    private var libraryDeletionPresented: Binding<Bool> {
        Binding(
            get: { model.pendingLibraryDeletion != nil },
            set: {
                if !$0 {
                    model.cancelLibraryDeletion()
                }
            }
        )
    }

    private var libraryOperationErrorPresented: Binding<Bool> {
        Binding(
            get: { model.libraryOperationError != nil },
            set: {
                if !$0 {
                    model.dismissLibraryOperationError()
                }
            }
        )
    }

    private var storeOperationFailurePresented: Binding<Bool> {
        Binding(
            get: { model.librarySession.store.operationFailure != nil },
            set: {
                if !$0 {
                    model.librarySession.store.dismissOperationFailure()
                }
            }
        )
    }
}

private struct CadenceSearchModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String
    @Binding var isPresented: Bool
    let prompt: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(
                text: $text,
                isPresented: $isPresented,
                placement: .toolbar,
                prompt: Text(prompt)
            )
        } else {
            content
        }
    }
}
