import Foundation

extension CadenceAppModel {
    func playSelectedProductionSmartCollection(
        shuffled: Bool = false
    ) {
        guard let selectedSmartCollection else {
            return
        }
        Task {
            var collectionTracks = await librarySession.store
                .completeSmartCollectionTracks(
                    for: selectedSmartCollection.rule
                )
            if shuffled {
                collectionTracks.shuffle()
            }
            guard let first = collectionTracks.first else {
                return
            }
            playProductionTrack(
                first,
                within: collectionTracks,
                source: selectedSmartCollectionID.map {
                    .smartCollection($0)
                }
            )
        }
    }

    @discardableResult
    func playSelectedSmartCollection() -> Bool {
        guard let collection = selectedSmartCollection else {
            return false
        }

        let visibleTracks = selectedSmartCollectionVisibleTracks
        let visibleIDs = visibleTracks.map(\.id)
        let selectedStartID = selectedTrackID.flatMap { selectedID in
            visibleIDs.contains(selectedID) ? selectedID : nil
        }

        return startPlaybackQueue(
            source: .smartCollection(collection.id),
            trackIDs: visibleIDs,
            startingAt: selectedStartID
        )
    }

    @discardableResult
    func playSelectedSmartCollectionTrack(_ track: TrackPreview) -> Bool {
        guard let collection = selectedSmartCollection else {
            return false
        }

        let visibleIDs = selectedSmartCollectionVisibleTracks.map(\.id)
        guard visibleIDs.contains(track.id) else {
            return false
        }

        return startPlaybackQueue(
            source: .smartCollection(collection.id),
            trackIDs: visibleIDs,
            startingAt: track.id
        )
    }

    @discardableResult
    func shuffleSelectedSmartCollection(
        using generator: inout some RandomNumberGenerator
    ) -> Bool {
        guard let collection = selectedSmartCollection else {
            return false
        }

        let canonicalIDs = selectedSmartCollectionCanonicalTracks.map(\.id)
        let shuffledIDs = PlaybackQueue.shuffledOrder(
            canonicalIDs,
            using: &generator
        )

        return startPlaybackQueue(
            source: .smartCollection(collection.id),
            trackIDs: shuffledIDs,
            startingAt: shuffledIDs.first,
            isShuffled: true
        )
    }
}
