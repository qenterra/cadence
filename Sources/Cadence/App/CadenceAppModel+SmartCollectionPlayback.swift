import Foundation

extension CadenceAppModel {
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
    func shuffleSelectedSmartCollection() -> Bool {
        var generator = SystemRandomNumberGenerator()
        return shuffleSelectedSmartCollection(using: &generator)
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
