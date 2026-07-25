import Foundation

extension CadenceAppModel {
    var isPlaybackWorkspacePresented: Bool {
        playbackWorkspace != .hidden
    }

    @discardableResult
    func presentNowPlaying() -> Bool {
        guard let currentTrack else {
            return false
        }

        if playbackWorkspace == .lyricsEditor {
            if isLyricDraftDirty {
                pendingLyricsTransition = .nowPlayingPanel(
                    selectedNowPlayingPanel
                )
            } else {
                performLyricsTransition(
                    .nowPlayingPanel(selectedNowPlayingPanel)
                )
            }
            return true
        }

        preparePlaybackQueueIfNeeded()
        selectedNowPlayingPanel = lastNowPlayingPanel
            ?? (lyricDocuments[currentTrack.id] == nil ? .queue : .lyrics)
        playbackWorkspace = .nowPlaying
        return true
    }

    @discardableResult
    func presentPlaybackQueue() -> Bool {
        guard currentTrack != nil || activePlaybackQueue != nil else {
            return false
        }

        if playbackWorkspace == .lyricsEditor {
            if isLyricDraftDirty {
                pendingLyricsTransition = .nowPlayingPanel(.queue)
            } else {
                performLyricsTransition(.nowPlayingPanel(.queue))
            }
            return true
        }

        preparePlaybackQueueIfNeeded()
        selectedNowPlayingPanel = .queue
        playbackWorkspace = .nowPlaying
        return true
    }

    func selectNowPlayingPanel(_ panel: NowPlayingPanel) {
        selectedNowPlayingPanel = panel
        lastNowPlayingPanel = panel
    }

    func dismissNowPlaying() {
        guard playbackWorkspace == .nowPlaying else {
            return
        }
        playbackWorkspace = .hidden
    }

    func requestClosePlaybackWorkspace() {
        switch playbackWorkspace {
        case .hidden:
            break
        case .nowPlaying:
            dismissNowPlaying()
        case .lyricsEditor:
            requestCloseLyricsEditor()
        }
    }

    func requestPlaybackQueueMove(by offset: Int) {
        let requiresConfirmation = playbackWorkspace == .lyricsEditor
            && isLyricDraftDirty
        if requiresConfirmation {
            pendingLyricsTransition = .playbackOffset(offset)
            return
        }

        let keepsEditorOpen = playbackWorkspace == .lyricsEditor
        performPlaybackQueueMove(by: offset)
        if keepsEditorOpen {
            replaceLyricDraftForCurrentTrack()
        }
    }

    func requestPlaybackWorkspaceNavigation(
        _ destination: NavigationDestination
    ) -> Bool {
        guard playbackWorkspace != .hidden else {
            return false
        }

        let requiresConfirmation = playbackWorkspace == .lyricsEditor
            && isLyricDraftDirty
        if requiresConfirmation {
            pendingLyricsTransition = .destination(destination)
        } else {
            performLyricsTransition(.destination(destination))
        }
        return true
    }

    func performLyricsTransition(_ target: LyricsTransitionTarget) {
        switch target {
        case .closeEditor:
            lyricDraft = nil
            playbackWorkspace = .nowPlaying
        case let .destination(destination):
            lyricDraft = nil
            playbackWorkspace = .hidden
            requestNavigationDestination(destination)
        case let .nowPlayingPanel(panel):
            lyricDraft = nil
            preparePlaybackQueueIfNeeded()
            selectedNowPlayingPanel = panel
            playbackWorkspace = .nowPlaying
        case let .playbackOffset(offset):
            lyricDraft = nil
            performPlaybackQueueMove(by: offset)
            replaceLyricDraftForCurrentTrack()
            playbackWorkspace = .lyricsEditor
        }
    }
}
