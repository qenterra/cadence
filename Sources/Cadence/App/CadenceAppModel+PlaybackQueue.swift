import Foundation

extension CadenceAppModel {
    @discardableResult
    func startPlaybackQueue(
        source: PlaybackQueue.Source,
        trackIDs: [TrackPreview.ID],
        startingAt trackID: TrackPreview.ID? = nil,
        isShuffled: Bool = false
    ) -> Bool {
        let availableTrackIDs = Set(tracks.map(\.id))
        let validTrackIDs = trackIDs.filter(availableTrackIDs.contains)
        let queue = PlaybackQueue(
            source: source,
            orderedTrackIDs: validTrackIDs,
            startingAt: trackID,
            isShuffled: isShuffled
        )
        guard
            let currentID = queue.currentTrackID,
            let currentTrack = tracks.first(where: { $0.id == currentID })
        else {
            return false
        }

        activePlaybackQueue = queue
        selectTrack(currentTrack)
        currentTrackID = currentTrack.id
        progress = 0
        isPlaying = true
        return true
    }

    func play(_ track: TrackPreview) {
        let albumTrackIDs = AlbumListeningProjection.canonicalTracks(
            tracks.filter { $0.albumID == track.albumID }
        ).map(\.id)
        startPlaybackQueue(
            source: .album(track.albumID),
            trackIDs: albumTrackIDs,
            startingAt: track.id
        )
    }

    @discardableResult
    func playAlbum(_ album: AlbumPreview) -> Bool {
        let albumTracks = AlbumListeningProjection.canonicalTracks(
            tracks.filter { $0.albumID == album.id }
        )
        let selectedID = selectedTrack.flatMap {
            $0.albumID == album.id ? $0.id : nil
        }
        return startPlaybackQueue(
            source: .album(album.id),
            trackIDs: albumTracks.map(\.id),
            startingAt: selectedID ?? albumTracks.first?.id
        )
    }

    func togglePlayback() {
        if let playbackCoordinator,
           playbackCoordinator.state.currentTrack != nil {
            playbackCoordinator.togglePlayback()
            return
        }
        guard currentTrackID != nil else {
            if let track = selectedTrack ?? tracks.first {
                play(track)
            }
            return
        }
        isPlaying.toggle()
    }

    func selectPreviousTrack() {
        if currentPlaybackTrack != nil {
            moveProductionQueue(by: -1)
            return
        }
        requestPlaybackQueueMove(by: -1)
    }

    func selectNextTrack() {
        if currentPlaybackTrack != nil {
            moveProductionQueue(by: 1)
            return
        }
        requestPlaybackQueueMove(by: 1)
    }

    @discardableResult
    func removeFromPlaybackQueue(
        _ trackIDs: [TrackPreview.ID],
        undoManager: UndoManager? = nil
    ) -> Bool {
        updatePlaybackQueue(
            actionName: "Remove from Queue",
            undoManager: undoManager
        ) { queue in
            queue.removeUpNext(trackIDs)
        }
    }

    @discardableResult
    func clearPlaybackQueue(
        undoManager: UndoManager? = nil
    ) -> Bool {
        updatePlaybackQueue(
            actionName: "Clear Up Next",
            undoManager: undoManager
        ) { queue in
            queue.clearUpNext()
        }
    }

    func performPlaybackQueueMove(by offset: Int) {
        preparePlaybackQueueIfNeeded()
        guard var queue = activePlaybackQueue else {
            return
        }

        let availableTrackIDs = Set(tracks.map(\.id))
        guard
            let nextID = queue.move(
                by: offset,
                availableTrackIDs: availableTrackIDs
            ),
            let track = tracks.first(where: { $0.id == nextID })
        else {
            return
        }

        activePlaybackQueue = queue
        selectTrack(track)
        currentTrackID = track.id
        progress = 0
    }

    func preparePlaybackQueueIfNeeded() {
        guard activePlaybackQueue == nil else {
            return
        }
        guard let anchor = currentTrack ?? selectedTrack ?? tracks.first else {
            return
        }

        let albumTrackIDs = AlbumListeningProjection.canonicalTracks(
            tracks.filter { $0.albumID == anchor.albumID }
        ).map(\.id)
        activePlaybackQueue = PlaybackQueue(
            source: .album(anchor.albumID),
            orderedTrackIDs: albumTrackIDs,
            startingAt: anchor.id
        )
    }

    private func updatePlaybackQueue(
        actionName: String,
        undoManager: UndoManager?,
        mutation: (inout PlaybackQueue) -> Bool
    ) -> Bool {
        preparePlaybackQueueIfNeeded()
        guard var queue = activePlaybackQueue else {
            return false
        }
        let previous = queue
        guard mutation(&queue) else {
            return false
        }

        activePlaybackQueue = queue
        registerPlaybackQueueUndo(
            restoring: previous,
            actionName: actionName,
            undoManager: undoManager
        )
        return true
    }

    private func registerPlaybackQueueUndo(
        restoring snapshot: PlaybackQueue,
        actionName: String,
        undoManager: UndoManager?
    ) {
        guard let undoManager else {
            return
        }

        undoManager.registerUndo(withTarget: self) { model in
            let redoSnapshot = model.activePlaybackQueue
            model.activePlaybackQueue = snapshot
            if let redoSnapshot {
                model.registerPlaybackQueueUndo(
                    restoring: redoSnapshot,
                    actionName: actionName,
                    undoManager: undoManager
                )
            }
        }
        undoManager.setActionName(actionName)
    }
}
