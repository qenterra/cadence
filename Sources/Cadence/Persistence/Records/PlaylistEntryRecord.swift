import Foundation
import SwiftData

@Model
final class PlaylistEntryRecord {
    #Index<PlaylistEntryRecord>(
        [\.playlistID, \.position],
        [\.playlistID, \.trackID],
        [\.trackID]
    )

    @Attribute(.unique) var id: UUID
    var playlistID: UUID
    var trackID: UUID
    var position: Int
    var dateAdded: Date

    init(
        id: UUID = UUID(),
        playlistID: UUID,
        trackID: UUID,
        position: Int,
        dateAdded: Date = .now
    ) {
        self.id = id
        self.playlistID = playlistID
        self.trackID = trackID
        self.position = position
        self.dateAdded = dateAdded
    }
}
