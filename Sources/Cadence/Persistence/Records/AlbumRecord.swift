import Foundation
import SwiftData

@Model
final class AlbumRecord {
    #Index<AlbumRecord>(
        [\.normalizedTitle],
        [\.normalizedTitle, \.sortIdentity],
        [\.year],
        [\.dateAdded]
    )

    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sortIdentity: String
    var title: String
    var normalizedTitle: String
    var year: Int?
    // Kept only to reopen V4 libraries. Cadence no longer reads or updates it.
    var dateAdded: Date
    var isFavorite: Bool
    var favoriteDate: Date?
    var trackCount: Int
    var totalDuration: TimeInterval
    var customArtworkID: UUID?
    var artist: ArtistRecord?

    @Relationship(deleteRule: .nullify, inverse: \TrackRecord.album)
    var tracks: [TrackRecord]

    init(
        id: UUID = UUID(),
        title: String,
        artist: ArtistRecord? = nil,
        year: Int? = nil,
        dateAdded: Date = .now,
        isFavorite: Bool = false,
        favoriteDate: Date? = nil,
        trackCount: Int = 0,
        totalDuration: TimeInterval = 0,
        customArtworkID: UUID? = nil
    ) {
        self.id = id
        sortIdentity = id.uuidString
        self.title = title
        normalizedTitle = SearchNormalizer.normalize(title)
        self.artist = artist
        self.year = year
        self.dateAdded = dateAdded
        self.isFavorite = isFavorite
        self.favoriteDate = favoriteDate
        self.trackCount = trackCount
        self.totalDuration = totalDuration
        self.customArtworkID = customArtworkID
        tracks = []
    }

    func rename(to title: String) {
        self.title = title
        normalizedTitle = SearchNormalizer.normalize(title)
    }
}
