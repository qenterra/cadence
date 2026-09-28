import Foundation

extension LibraryPlaylistProjection {
    init(
        id: UUID,
        name: String,
        trackCount: Int,
        totalDuration: TimeInterval,
        modifiedAt: Date,
        customArtworkID: UUID?
    ) {
        self.id = id
        self.name = name
        userDescription = nil
        self.trackCount = trackCount
        self.totalDuration = totalDuration
        self.modifiedAt = modifiedAt
        self.customArtworkID = customArtworkID
    }
}
