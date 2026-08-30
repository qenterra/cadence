import SwiftUI

enum DestinationPresentation: Hashable, Sendable {
    case loading
    case content

    static func resolve(
        hasResidentContent: Bool,
        isLoading: Bool
    ) -> DestinationPresentation {
        isLoading && !hasResidentContent ? .loading : .content
    }

    static func resolve(
        destination: NavigationDestination,
        hasResidentContent: Bool,
        isLoading: Bool
    ) -> DestinationPresentation {
        if destination == .smartCollections {
            return .content
        }
        return resolve(
            hasResidentContent: hasResidentContent,
            isLoading: isLoading
        )
    }
}

struct CadenceRootView: View {
    @Environment(\.visualRegressionUsesStableSystemControls)
    private var usesStableSystemControls
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: CadenceAppModel
    @State var isSearchPresented = false
    @State private var cadenceModeSession: CadenceModeSession
    @State private var folderIconController = LibraryFolderIconController()
    @AppStorage(CadenceModePreferences.isEnabledKey)
    private var isCadenceModeEnabled = CadenceModeOptions.default.isEnabled
    @AppStorage(CadenceModePreferences.reactsToBassKey)
    private var cadenceModeReactsToBass = CadenceModeOptions.default.reactsToBass
    @AppStorage(CadenceModePreferences.showsLyricsKey)
    private var cadenceModeShowsLyrics = CadenceModeOptions.default.showsLyrics
    @AppStorage(CadenceModePreferences.showsTrackInformationKey)
    private var cadenceModeShowsTrackInformation =
        CadenceModeOptions.default.showsTrackInformation
    @AppStorage(CadenceModePreferences.staysActiveKey)
    private var staysInCadenceMode = CadenceModeOptions.default.staysActive
    @AppStorage(CadencePreferences.Keys.catalogCardSize)
    private var catalogCardSizeRaw = CatalogCardSize.automatic.rawValue

    init(
        model: CadenceAppModel,
        cadenceModeSession: CadenceModeSession = CadenceModeSession()
    ) {
        self.model = model
        _cadenceModeSession = State(initialValue: cadenceModeSession)
    }

    var body: some View {
        WindowContentLayout {
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
                PlayerBar(
                    model: model,
                    suspendsProgressAnimation: cadenceModeSession.isActive
                )
            }
        }
        .background(CadenceTheme.contentBackground)
        .environment(
            \.catalogCardSize,
            CatalogCardSize(rawValue: catalogCardSizeRaw) ?? .automatic
        )
        .background {
            ZStack {
                AppPlaybackKeyboardCapture(
                    isLocallyOwned: ownsSpaceLocally
                ) { focus in
                    _ = AppCommandRouter(model: model).handle(
                        .togglePlayback,
                        focus: focus
                    )
                }
                CadenceModeInputCapture(
                    model: model,
                    session: cadenceModeSession,
                    isEnabled: cadenceModeOptions.isEnabled
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .toolbarBackground(
            CadenceTheme.opaqueSurface,
            for: .windowToolbar
        )
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .modifier(
            CadenceSearchModifier(
                isEnabled: supportsSearch,
                text: activeSearchBinding,
                isPresented: $isSearchPresented,
                prompt: searchHelp
            )
        )
        .lyricsDraftTransitionAlert(model: model)
        .artworkManagement(model: model)
        .alert(
            "New Playlist",
            isPresented: playlistCreationPresented
        ) {
            TextField("Playlist Name", text: pendingPlaylistName)
            Button("Create") {
                Task {
                    await model.confirmPlaylistCreation()
                }
            }
            .cadenceActionTint(.confirmation)
            .disabled(
                model.pendingPlaylistCreation?.name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty != false
            )
            Button("Cancel", role: .cancel) {
                model.cancelPlaylistCreation()
            }
        } message: {
            let count = model.pendingPlaylistCreation?.trackIDs.count ?? 0
            Text(
                count == 1
                    ? "Create a playlist and add the selected track."
                    : "Create a playlist and add \(count) selected tracks."
            )
        }
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
            .cadenceActionTint(.destructive)
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
            "Couldn’t Complete Library Operation",
            isPresented: libraryOperationErrorPresented
        ) {
            Button("Dismiss", role: .cancel) {
                model.dismissLibraryOperationError()
            }
        } message: {
            Text(
                ProductErrorMessage(
                    detail: model.libraryOperationError
                        ?? String(localized: "Cadence could not complete the library operation."),
                    preservedState: String(localized: "Cadence kept the last confirmed library state."),
                    recoveryAction: String(localized: "Try the action again or dismiss this message.")
                ).text
            )
        }
        .alert(
            model.librarySession.store.operationFailure?.title
                ?? "Couldn’t Complete Library Operation",
            isPresented: storeOperationFailurePresented
        ) {
            if model.librarySession.store.operationFailure?.isRetryable == true {
                Button("Retry") {
                    Task {
                        await model.librarySession.store.retryOperationFailure()
                    }
                }
            }
            Button("Dismiss") {
                model.librarySession.store.dismissOperationFailure()
            }
        } message: {
            Text(
                ProductErrorMessage(
                    detail: model.librarySession.store.operationFailure?.message
                        ?? String(localized: "Cadence could not complete the library operation."),
                    preservedState: String(localized: "Cadence kept the last confirmed library state."),
                    recoveryAction: model.librarySession.store.operationFailure?.isRetryable == true
                        ? String(localized: "Retry or dismiss this message.")
                        : String(localized: "Try the action again or dismiss this message.")
                ).text
            )
        }
        .alert(
            "Couldn’t Open Audio",
            isPresented: externalAudioErrorPresented
        ) {
            Button("Dismiss", role: .cancel) {
                model.externalAudioOpenError = nil
            }
        } message: {
            Text(
                ProductErrorMessage(
                    detail: model.externalAudioOpenError
                        ?? String(localized: "Cadence could not open the selected audio file."),
                    preservedState: String(localized: "The current queue is unchanged."),
                    recoveryAction: String(localized: "Choose another file or dismiss this message.")
                ).text
            )
        }
        .alert(
            "Some Files Were Skipped",
            isPresented: externalAudioNoticePresented
        ) {
            Button("OK", role: .cancel) {
                model.externalAudioNotice = nil
            }
        } message: {
            Text(
                model.externalAudioNotice
                    ?? "Cadence opened the supported audio files."
            )
        }
        .task {
            synchronizeCadenceModeOptions(cadenceModeOptions)
            model.activateSystemMediaSession()
            await model.recoverManagedLibraryIfNeeded()
            await model.repairImportedMetadataIfNeeded()
            await model.loadInitialPersistentFeatures()
        }
        .task(id: model.currentPlaybackTrack?.id) {
            guard !usesStableSystemControls,
                  !model.isCurrentPlaybackExternal,
                  let trackID = model.currentPlaybackTrack?.id
            else {
                return
            }
            await model.librarySession.store.recordRecentlyPlayed(
                trackID: trackID
            )
        }
        .task(id: folderIconRefreshID) {
            guard let packageURL = model.librarySession.location?.packageURL else {
                return
            }
            folderIconController.applyIcon(
                to: packageURL,
                appearance: LibraryFolderAppearance(colorScheme: colorScheme)
            )
        }
        .onDisappear {
            cadenceModeSession.deactivate()
            model.shutdownPlayback()
        }
        .onChange(of: model.selectedDestination) {
            dismissSearch()
        }
        .onChange(of: cadenceModeOptions) { _, options in
            synchronizeCadenceModeOptions(options)
        }
        .onKeyPress(.escape, phases: .down) { _ in
            guard isSearchPresented || !activeSearchQuery.isEmpty else {
                return .ignored
            }
            dismissSearch()
            return .handled
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
    var ownsSpaceLocally: Bool {
        model.playbackWorkspace == .lyricsEditor
            || (
                model.selectedDestination == .importMusic
                    && model.importPreviewStage == .review
            )
    }

    var folderIconRefreshID: String {
        let path = model.librarySession.location?.packageURL.path ?? "none"
        let appearance = colorScheme == .dark ? "dark" : "light"
        let availability = String(describing: model.librarySession.availability)
        return "\(path)|\(appearance)|\(availability)|\(model.libraryResetRevision)"
    }

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

    private var cadenceModeOptions: CadenceModeOptions {
        CadenceModeOptions(
            isEnabled: isCadenceModeEnabled,
            reactsToBass: cadenceModeReactsToBass,
            showsLyrics: cadenceModeShowsLyrics,
            showsTrackInformation: cadenceModeShowsTrackInformation,
            staysActive: staysInCadenceMode
        )
    }

    private func synchronizeCadenceModeOptions(
        _ options: CadenceModeOptions
    ) {
        cadenceModeSession.setEnabled(options.isEnabled)
        cadenceModeSession.setStaysActive(options.staysActive)
    }

    private var navigationSelection: Binding<NavigationDestination> {
        Binding(
            get: { model.selectedDestination },
            set: model.requestNavigationDestination
        )
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if shouldPresentProductionSearch {
            ProductionSearchResultsView(
                model: model,
                store: model.librarySession.store
            )
        } else {
            playbackOrDestinationContent
        }
    }

    @ViewBuilder
    private var playbackOrDestinationContent: some View {
        switch model.playbackWorkspace {
        case .nowPlaying:
            NowPlayingView(
                model: model,
                cadenceModeSession: cadenceModeSession,
                cadenceModeOptions: cadenceModeOptions
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
            ProgressView("Opening Cadence Library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case let .failed(failure) = model.librarySession.availability {
            LibraryUnavailableView(failure: failure) {
                Task {
                    await model.retryManagedLibrary()
                }
            } locate: {
                model.locateUnavailableLibrary()
            }
        } else {
            Group {
                if destinationPresentation == .loading {
                    ProgressView("Loading \(model.selectedDestination.title)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    destinationPage
                }
            }
            .id(destinationTransitionIdentity)
            .transition(.opacity)
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: CadenceTheme.motionReplace),
                value: destinationTransitionIdentity
            )
        }
    }

    @ViewBuilder
    private var destinationPage: some View {
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

    private var destinationPresentation: DestinationPresentation {
        let store = model.librarySession.store
        let hasResidentContent: Bool
        let isLoading: Bool
        switch model.selectedDestination {
        case .home:
            hasResidentContent = store.catalogCounts.liveTrackCount > 0
            isLoading = store.availability == .loading
        case .library:
            hasResidentContent = !store.artists.isEmpty
                || !store.albums.isEmpty
                || !store.tracks.isEmpty
            isLoading = store.availability == .loading
        case .allTracks:
            hasResidentContent = store.catalogCounts.liveTrackCount > 0
            isLoading = store.availability == .loading
        case .albums:
            hasResidentContent = !store.albums.isEmpty
            isLoading = store.availability == .loading
                || store.isLoadingNextAlbums
        case .artists:
            hasResidentContent = !store.artists.isEmpty
            isLoading = store.availability == .loading
                || store.isLoadingNextArtists
        case .favorites:
            hasResidentContent = !store.favoriteTracks.isEmpty
                || !store.favoriteAlbums.isEmpty
                || !store.favoriteArtists.isEmpty
            isLoading = store.availability == .loading
        case .tags:
            hasResidentContent = !store.tags.isEmpty
            isLoading = store.availability == .loading
                || store.isLoadingNextTags
        case .smartCollections:
            hasResidentContent = !model.smartCollections.isEmpty
            isLoading = store.isLoadingSmartCollectionData
        case .playlists:
            hasResidentContent = !store.playlists.isEmpty
            isLoading = store.playlistListState == .loading
        case .importMusic:
            hasResidentContent = true
            isLoading = false
        case .trash:
            hasResidentContent = !store.trashOperations.isEmpty
            isLoading = store.availability == .loading
        }
        return DestinationPresentation.resolve(
            destination: model.selectedDestination,
            hasResidentContent: hasResidentContent,
            isLoading: isLoading
        )
    }

    private var destinationTransitionIdentity: String {
        "\(model.selectedDestination.rawValue)-\(destinationPresentation)"
    }
}
