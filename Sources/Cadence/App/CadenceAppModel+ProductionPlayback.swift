import Foundation

extension CadenceAppModel {
    func playProductionTrack(
        _ track: LibraryTrackProjection,
        within queueTracks: [LibraryTrackProjection],
        source requestedSource: PlaybackQueueSource? = nil,
        isShuffled: Bool = false
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
            _ = await playbackCoordinator.startQueue(
                source: source,
                trackIDs: trackIDs,
                startingAt: track.id,
                isShuffled: isShuffled
            )
        }
    }

    func isCurrentProductionTrack(
        _ trackID: UUID
    ) -> Bool {
        currentPlaybackTrack?.id == trackID
    }

    var productionPlaybackQueueTracks: [LibraryTrackProjection] {
        guard
            let queue = playbackCoordinator?.state.queue,
            !librarySession.store.tracks.isEmpty
        else {
            return []
        }
        let tracksByID = Dictionary(
            uniqueKeysWithValues: librarySession.store.tracks.map {
                ($0.id, $0)
            }
        )
        return queue.orderedTrackIDs.compactMap {
            tracksByID[$0]
        }
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
        before targetTrackID: UUID?
    ) -> Bool {
        playbackCoordinator?.reorderUpNext(
            trackIDs,
            before: targetTrackID
        ) ?? false
    }

    @discardableResult
    func removeFromProductionQueue(
        _ trackIDs: [UUID]
    ) -> Bool {
        playbackCoordinator?.removeUpNext(trackIDs) ?? false
    }

    @discardableResult
    func clearProductionQueue() -> Bool {
        playbackCoordinator?.clearUpNext() ?? false
    }

    func activateSystemMediaSession() {
        playbackCoordinator?.activateSystemMediaSession()
    }

    func shutdownPlayback() {
        playbackCoordinator?.shutdown()
    }

    func loadProductionLyrics(
        for track: PlaybackTrack
    ) async -> LyricDocument? {
        try? await librarySession.store.lyricsDocument(trackID: track.id)
    }
}
