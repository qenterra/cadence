import SwiftUI

struct CadenceRootView: View {
    @Environment(\.visualRegressionUsesStableSystemControls)
    private var usesStableSystemControls
    @Bindable var model: CadenceAppModel
    @State var isSearchPresented = false
    @State private var cadenceModeSession: CadenceModeSession

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
        .background {
            CadenceModeInputCapture(
                model: model,
                session: cadenceModeSession
            )
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
}
