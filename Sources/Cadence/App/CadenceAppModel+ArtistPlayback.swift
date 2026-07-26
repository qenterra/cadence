import Foundation

extension CadenceAppModel {
    @discardableResult
    func playArtist(_ artist: ArtistPreview) -> Bool {
        let artistTracks = canonicalTracks(for: artist)
        let selectedID = selectedTrack.flatMap {
            $0.artistID == artist.id ? $0.id : nil
        }
        return startPlaybackQueue(
            source: .artist(artist.id),
            trackIDs: artistTracks.map(\.id),
            startingAt: selectedID ?? artistTracks.first?.id
        )
    }

    @discardableResult
    func playArtistTrack(
        _ track: TrackPreview,
        in artist: ArtistPreview
    ) -> Bool {
        guard track.artistID == artist.id else {
            return false
        }
        return startPlaybackQueue(
            source: .artist(artist.id),
            trackIDs: canonicalTracks(for: artist).map(\.id),
            startingAt: track.id
        )
    }

    @discardableResult
    func shuffleArtist(
        _ artist: ArtistPreview,
        using generator: inout some RandomNumberGenerator
    ) -> Bool {
        let artistTrackIDs = canonicalTracks(for: artist).map(\.id)
        let shuffled = PlaybackQueue.shuffledOrder(
            artistTrackIDs,
            using: &generator
        )
        return startPlaybackQueue(
            source: .artist(artist.id),
            trackIDs: shuffled,
            startingAt: shuffled.first,
            isShuffled: true
        )
    }

    @discardableResult
    func shuffleArtist(_ artist: ArtistPreview) -> Bool {
        var generator = SystemRandomNumberGenerator()
        return shuffleArtist(artist, using: &generator)
    }
}
