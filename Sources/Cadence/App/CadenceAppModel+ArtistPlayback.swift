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
}
