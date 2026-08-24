import Foundation

extension CadenceAppModel {
    var isPlaybackWorkspacePresented: Bool {
        playbackWorkspace != .hidden
    }

    @discardableResult
    func presentNowPlaying() -> Bool {
        presentNowPlaying(preferredPanel: nil)
    }

    @discardableResult
    func presentNowPlaying(panel: NowPlayingPanel) -> Bool {
        presentNowPlaying(preferredPanel: panel)
    }

    private func presentNowPlaying(
        preferredPanel: NowPlayingPanel?
    ) -> Bool {
        guard hasCurrentPlaybackItem else {
            return false
        }

        if playbackWorkspace == .lyricsEditor {
            let panel = preferredPanel ?? selectedNowPlayingPanel
            if isLyricDraftDirty {
                pendingLyricsTransition = .nowPlayingPanel(panel)
            } else {
                performLyricsTransition(.nowPlayingPanel(panel))
            }
            return true
        }

        preparePlaybackQueueIfNeeded()
        if let preferredPanel {
            selectedNowPlayingPanel = preferredPanel
        } else if let currentTrack {
            selectedNowPlayingPanel = lastNowPlayingPanel
                ?? (lyricDocuments[currentTrack.id] == nil ? .queue : .lyrics)
        } else {
            selectedNowPlayingPanel = lastNowPlayingPanel ?? .queue
        }
        playbackWorkspace = .nowPlaying
        return true
    }

    @discardableResult
    func presentPlaybackQueue() -> Bool {
        guard hasCurrentPlaybackItem || activePlaybackQueue != nil else {
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

    func requestPlaybackQueueMove(by offset: Int) {
        if currentPlaybackTrack != nil {
            if playbackWorkspace == .lyricsEditor, isLyricDraftDirty {
                pendingLyricsTransition = .playbackOffset(offset)
                return
            }
            if playbackWorkspace == .lyricsEditor {
                lyricDraft = nil
                playbackWorkspace = .nowPlaying
            }
            moveProductionQueue(by: offset)
            return
        }
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
            isLoadingLyricDraft = false
            lyricLoadRequestID = nil
            lyricPersistenceError = nil
            playbackWorkspace = .nowPlaying
        case let .destination(destination):
            lyricDraft = nil
            isLoadingLyricDraft = false
            lyricLoadRequestID = nil
            lyricPersistenceError = nil
            lyricsSearchTarget = nil
            playbackWorkspace = .hidden
            requestNavigationDestination(destination)
        case let .nowPlayingPanel(panel):
            lyricDraft = nil
            isLoadingLyricDraft = false
            lyricLoadRequestID = nil
            lyricPersistenceError = nil
            preparePlaybackQueueIfNeeded()
            selectedNowPlayingPanel = panel
            playbackWorkspace = .nowPlaying
        case let .playbackOffset(offset):
            lyricDraft = nil
            isLoadingLyricDraft = false
            lyricLoadRequestID = nil
            lyricPersistenceError = nil
            if currentPlaybackTrack != nil {
                moveProductionQueue(by: offset)
                playbackWorkspace = .nowPlaying
                return
            }
            performPlaybackQueueMove(by: offset)
            replaceLyricDraftForCurrentTrack()
            playbackWorkspace = .lyricsEditor
        }
    }

    func presentLyricsSearchResult(
        _ result: LyricsCatalogSearchResult
    ) {
        lyricsSearchTarget = result
        playbackWorkspace = .lyricsSearch
    }

    func dismissLyricsSearchResult() {
        lyricsSearchTarget = nil
        playbackWorkspace = .hidden
    }
}
