import Foundation

extension PlaybackCoordinator {
    @discardableResult
    func playQueueItem(
        id trackID: UUID
    ) async -> Bool {
        guard var queue = state.queue, queue.move(to: trackID) else {
            return false
        }
        state.queue = queue
        publishState()
        return await loadCurrent(startTime: 0, autoplay: true)
    }

    @discardableResult
    func reorderUpNext(
        _ trackIDs: [UUID],
        before targetTrackID: UUID?
    ) -> Bool {
        updateQueue {
            $0.reorderUpNext(trackIDs, before: targetTrackID)
        }
    }

    @discardableResult
    func removeUpNext(
        _ trackIDs: [UUID]
    ) -> Bool {
        updateQueue {
            $0.removeUpNext(trackIDs)
        }
    }

    @discardableResult
    func clearUpNext() -> Bool {
        updateQueue {
            $0.clearUpNext()
        }
    }

    @discardableResult
    func playNext(
        _ trackIDs: [UUID]
    ) -> Bool {
        updateQueue {
            $0.playNext(trackIDs)
        }
    }

    @discardableResult
    func addToEnd(
        _ trackIDs: [UUID]
    ) -> Bool {
        updateQueue {
            $0.addToEnd(trackIDs)
        }
    }

    @discardableResult
    func restoreQueueSnapshot(
        _ snapshot: PlaybackQueueState
    ) -> Bool {
        guard
            let currentQueue = state.queue,
            snapshot.currentTrackID == currentQueue.currentTrackID,
            snapshot.currentTrackID == state.currentTrack?.id
        else {
            return false
        }
        state.queue = snapshot
        publishState()
        Task {
            await prepareFollowingTrack()
        }
        return true
    }

    private func updateQueue(
        mutation: (inout PlaybackQueueState) -> Bool
    ) -> Bool {
        guard var queue = state.queue, mutation(&queue) else {
            return false
        }
        state.queue = queue
        publishState()
        Task {
            await prepareFollowingTrack()
        }
        return true
    }
}
