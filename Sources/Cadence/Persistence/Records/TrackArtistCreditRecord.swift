import Foundation
import SwiftData

@Model
final class TrackArtistCreditRecord {
    #Index<TrackArtistCreditRecord>(
        [\.trackID],
        [\.artistID],
        [\.trackID, \.position]
    )

    @Attribute(.unique) var id: UUID
    var trackID: UUID
    var artistID: UUID
    var position: Int
    var displayArtistName: String

    init(
        id: UUID = UUID(),
        track: TrackRecord,
        artist: ArtistRecord,
        position: Int,
        displayArtistName: String
    ) {
        self.id = id
        trackID = track.id
        artistID = artist.id
        self.position = position
        self.displayArtistName = displayArtistName
    }
}
