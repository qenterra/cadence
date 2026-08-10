import Foundation

extension CadenceAppModel {
    func playProductionTrack(
        _ track: LibraryTrackProjection,
        within queueTracks: [LibraryTrackProjection],
        source requestedSource: PlaybackQueueSource? = nil,
        isShuffled: Bool = false,
        startingAt time: TimeInterval? = nil
    ) {
        guard let playbackCoordinator else {
            return
        }
        let source: PlaybackQueueSource = requestedSource
            ?? track.albumID.map { .album($0) }
            ?? .adHoc
        Task {
            let trackIDs = if source == .allTracks {
                await librarySession.store.allTrackIDs()
            } else {
                queueTracks.map(\.id)
            }
            let didStart = await playbackCoordinator.startQueue(
                source: source,
                trackIDs: trackIDs,
                startingAt: track.id,
                isShuffled: isShuffled
            )
            if didStart, let time, time > 0 {
                await playbackCoordinator.seek(to: time)
            }
        }
    }

    func isCurrentProductionTrack(
        _ trackID: UUID
    ) -> Bool {
        playbackCoordinator?.playbackIndicator.currentTrackID == trackID
    }

    var isCurrentProductionTrackPlaying: Bool {
        playbackCoordinator?.playbackIndicator.isPlaying ?? previewIsPlaying
    }

    var productionPlaybackQueueTracks: [PlaybackQueueTrackProjection] {
        librarySession.store.playbackQueueTracks
    }

    func loadProductionPlaybackQueueTracks() async {
        await librarySession.store.loadPlaybackQueueTracks(
            ids: playbackCoordinator?.state.queue?.orderedTrackIDs ?? []
        )
    }

    func moveProductionQueue(
        by offset: Int
    ) {
        guard let playbackCoordinator else {
            return
        }
        Task {
            if offset < 0 {
                await playbackCoordinator.previous()
            } else {
                await playbackCoordinator.next()
            }
        }
    }

    func playProductionQueueItem(
        id trackID: UUID
    ) {
        guard let playbackCoordinator else {
            return
        }
        Task {
            _ = await playbackCoordinator.playQueueItem(id: trackID)
        }
    }

    func seekProductionPlayback(
        to time: TimeInterval
    ) {
        guard let playbackCoordinator else {
            return
        }
        Task {
            await playbackCoordinator.seek(to: time)
        }
    }

    @discardableResult
    func reorderProductionQueue(
        _ trackIDs: [UUID],
        before targetTrackID: UUID?,
        undoManager: UndoManager? = nil
    ) -> Bool {
        updateProductionQueue(
            actionName: "Reorder Queue",
            undoManager: undoManager
        ) { coordinator in
            coordinator.reorderUpNext(
                trackIDs,
                before: targetTrackID
            )
        }
    }

    @discardableResult
    func removeFromProductionQueue(
        _ trackIDs: [UUID],
        undoManager: UndoManager? = nil
    ) -> Bool {
        updateProductionQueue(
            actionName: "Remove from Queue",
            undoManager: undoManager
        ) { coordinator in
            coordinator.removeUpNext(trackIDs)
        }
    }

    @discardableResult
    func clearProductionQueue(
        undoManager: UndoManager? = nil
    ) -> Bool {
        updateProductionQueue(
            actionName: "Clear Up Next",
            undoManager: undoManager
        ) { coordinator in
            coordinator.clearUpNext()
        }
    }

    @discardableResult
    func playProductionNext(
        _ trackIDs: [UUID],
        undoManager: UndoManager? = nil
    ) -> Bool {
        updateProductionQueue(
            actionName: "Play Next",
            undoManager: undoManager
        ) { coordinator in
            coordinator.playNext(trackIDs)
        }
    }

    @discardableResult
    func addToProductionQueue(
        _ trackIDs: [UUID],
        undoManager: UndoManager? = nil
    ) -> Bool {
        updateProductionQueue(
            actionName: "Add to Queue",
            undoManager: undoManager
        ) { coordinator in
            coordinator.addToEnd(trackIDs)
        }
    }

    func activateSystemMediaSession() {
        playbackCoordinator?.activateSystemMediaSession()
    }

    var playbackOutputRoute: AudioRouteSnapshot {
        playbackCoordinator?.state.audioPath?.outputRoute
            ?? playbackCoordinator?.outputRoute
            ?? .unknown
    }

    var playbackPathStatus: String {
        guard let path = playbackCoordinator?.state.audioPath else {
            return "No active playback path"
        }
        return path.backend == .pcm
            ? "Cadence PCM renderer"
            : "System native renderer"
    }

    func retryPlaybackFailure() {
        Task {
            _ = await playbackCoordinator?.retryFailedCurrent()
        }
    }

    func skipPlaybackFailure() {
        Task {
            await playbackCoordinator?.skipFailedTrack()
        }
    }

    func shutdownPlayback() {
        playbackCoordinator?.shutdown()
    }

    func loadProductionLyrics(
        for track: PlaybackTrack
    ) async -> LyricDocument? {
        try? await librarySession.store.lyricsDocument(trackID: track.id)
    }

    func updateProductionLyricLine(
        in document: LyricDocument,
        lineID: LyricLine.ID,
        text: String
    ) async -> LyricDocument? {
        guard let updated = document.replacingText(for: lineID, with: text) else {
            return nil
        }
        do {
            try await librarySession.store.saveLyrics(updated)
            lyricsRevision += 1
            return updated
        } catch {
            libraryOperationError = error.localizedDescription
            return nil
        }
    }

    private func updateProductionQueue(
        actionName: String,
        undoManager: UndoManager?,
        mutation: (PlaybackCoordinator) -> Bool
    ) -> Bool {
        guard
            let playbackCoordinator,
            let previous = playbackCoordinator.state.queue,
            mutation(playbackCoordinator)
        else {
            return false
        }
        registerProductionQueueUndo(
            restoring: previous,
            actionName: actionName,
            undoManager: undoManager
        )
        return true
    }

    private func registerProductionQueueUndo(
        restoring snapshot: PlaybackQueueState,
        actionName: String,
        undoManager: UndoManager?
    ) {
        guard let undoManager else {
            return
        }
        undoManager.registerUndo(withTarget: self) { [weak undoManager] model in
            guard
                let undoManager,
                let coordinator = model.playbackCoordinator,
                let redoSnapshot = coordinator.state.queue,
                coordinator.restoreQueueSnapshot(snapshot)
            else {
                return
            }
            model.registerProductionQueueUndo(
                restoring: redoSnapshot,
                actionName: actionName,
                undoManager: undoManager
            )
        }
        undoManager.setActionName(actionName)
    }
}
