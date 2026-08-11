import Foundation

extension LibraryStore {
    func loadPlaybackQueueTracks(
        ids: [UUID]
    ) async {
        let ids = Array(ids.prefix(
            PlaybackQueuePresentation.maximumUpNextCount + 1
        ))
        playbackQueueProjectionGeneration += 1
        let generation = playbackQueueProjectionGeneration

        guard !ids.isEmpty else {
            playbackQueueTracks = []
            playbackQueueProjectionError = nil
            isLoadingPlaybackQueueTracks = false
            return
        }

        let currentByID = Dictionary(
            playbackQueueTracks.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        playbackQueueTracks = ids.map { id in
            currentByID[id] ?? PlaybackQueueTrackProjection(
                id: id,
                state: .loading
            )
        }
        playbackQueueProjectionError = nil

        guard let repository else {
            playbackQueueTracks = ids.map {
                PlaybackQueueTrackProjection(id: $0, state: .unavailable)
            }
            isLoadingPlaybackQueueTracks = false
            return
        }

        isLoadingPlaybackQueueTracks = true
        do {
            let projections = try await repository.playbackQueueTracks(
                ids: ids
            )
            guard generation == playbackQueueProjectionGeneration else {
                return
            }
            playbackQueueTracks = projections
            isLoadingPlaybackQueueTracks = false
        } catch {
            guard generation == playbackQueueProjectionGeneration else {
                return
            }
            finishPlaybackQueueFailure(
                error,
                ids: ids,
                currentByID: currentByID
            )
        }
    }

    private func finishPlaybackQueueFailure(
        _ error: Error,
        ids: [UUID],
        currentByID: [UUID: PlaybackQueueTrackProjection]
    ) {
        let message = error.localizedDescription
        playbackQueueTracks = ids.map { id in
            if let current = currentByID[id], current.track != nil {
                current
            } else {
                PlaybackQueueTrackProjection(
                    id: id,
                    state: .failed(message)
                )
            }
        }
        playbackQueueProjectionError = LibraryStoreFailure(message: message)
        isLoadingPlaybackQueueTracks = false
    }
}
