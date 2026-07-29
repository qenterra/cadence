import SwiftUI

struct CadenceRootView: View {
    @Bindable var model: CadenceAppModel

    @FocusState private var isSearchFocused: Bool
    @State private var isSearchPresented = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 0) {
                    NavigationRail(
                        selection: navigationSelection,
                        suppressesSelection: model.isPlaybackWorkspacePresented
                    )
                    Divider()
                    workspaceContent
                }

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

            Divider()
            PlayerBar(model: model)
        }
        .background(CadenceTheme.contentBackground)
        .toolbarBackground(
            CadenceTheme.contentBackground,
            for: .windowToolbar
        )
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.playbackWorkspace == .hidden, supportsSearch {
                    searchButton
                }

                Menu {
                    Button("Import Music", systemImage: "folder.badge.plus") {
                        model.requestNavigationDestination(.importMusic)
                    }

                    Divider()

                    Button("Settings", systemImage: "gearshape") {
                        model.requestNavigationDestination(.settings)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .help("More")
            }
        }
        .lyricsDraftTransitionAlert(model: model)
        .artworkManagement(model: model)
        .confirmationDialog(
            "Move to Trash?",
            isPresented: libraryDeletionPresented,
            presenting: model.pendingLibraryDeletion
        ) { _ in
            Button("Move to Trash", role: .destructive) {
                Task {
                    await model.confirmLibraryDeletion()
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
        .task {
            model.activateSystemMediaSession()
            await model.recoverManagedLibraryIfNeeded()
            await model.repairImportedMetadataIfNeeded()
            let needsInitialLoad = model.librarySession.availability == .ready
                && model.librarySession.store.tracks.isEmpty
            if needsInitialLoad {
                await model.librarySession.store.loadInitialLibrary()
            }
            await model.librarySession.store.loadPlaylists()
        }
        .onDisappear {
            model.shutdownPlayback()
        }
    }
}

private extension CadenceRootView {
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
            NowPlayingView(model: model)
        case .lyricsEditor:
            LyricsEditorView(model: model)
        case .hidden:
            destinationContent
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        if case let .failed(failure) = model.librarySession.availability {
            LibraryUnavailableView(failure: failure)
        } else if shouldPresentProductionSearch {
            ProductionSearchResultsView(
                model: model,
                store: model.librarySession.store
            )
        } else {
            switch model.selectedDestination {
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
            case .settings:
                ProductionSettingsView(model: model)
            }
        }
    }

    private var supportsSearch: Bool {
        switch model.selectedDestination {
        case .library, .allTracks, .albums, .artists, .tags,
             .smartCollections, .playlists:
            true
        case .importMusic, .trash, .settings:
            false
        }
    }

    private var searchButton: some View {
        Button {
            isSearchPresented.toggle()
        } label: {
            Image(
                systemName: activeSearchQuery.isEmpty
                    ? "magnifyingglass"
                    : "magnifyingglass.circle.fill"
            )
        }
        .help(searchHelp)
        .keyboardShortcut("f", modifiers: .command)
        .popover(isPresented: $isSearchPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                if isProductionCatalog {
                    TextField(
                        "Search Library",
                        text: productionSearchBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                } else if model.selectedDestination == .albums {
                    TextField("Search Albums", text: $model.albumSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFocused)
                } else if model.selectedDestination == .artists {
                    TextField("Search Artists", text: $model.artistSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFocused)
                } else {
                    TextField("Search Library", text: $model.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFocused)

                    Picker("Scope", selection: $model.searchScope) {
                        ForEach(LibrarySearchScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(16)
            .frame(width: 280)
            .onAppear {
                isSearchFocused = true
            }
        }
    }

    private var activeSearchQuery: String {
        if isProductionCatalog {
            return model.librarySession.store.catalogSearchQuery
        }
        return switch model.selectedDestination {
        case .albums:
            model.albumSearchQuery
        case .artists:
            model.artistSearchQuery
        default:
            model.searchQuery
        }
    }

    private var searchHelp: String {
        if isProductionCatalog {
            return "Search Library"
        }
        return switch model.selectedDestination {
        case .albums:
            "Search Albums"
        case .artists:
            "Search Artists"
        default:
            "Search Library"
        }
    }

    private var isProductionCatalog: Bool {
        model.librarySession.availability != .preview
    }

    private var shouldPresentProductionSearch: Bool {
        isProductionCatalog
            && supportsSearch
            && !SearchNormalizer.normalize(activeSearchQuery).isEmpty
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
}
