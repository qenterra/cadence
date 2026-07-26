import Foundation
import SwiftData

@Model
final class ArtistRecord {
    #Index<ArtistRecord>(
        [\.normalizedName],
        [\.normalizedName, \.sortIdentity],
        [\.favoriteDate]
    )

    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sortIdentity: String
    var name: String
    var normalizedName: String
    var isFavorite: Bool
    var favoriteDate: Date?
    var trackCount: Int
    var albumCount: Int
    var customArtworkID: UUID?

    @Relationship(deleteRule: .nullify, inverse: \TrackRecord.artist)
    var tracks: [TrackRecord]

    @Relationship(deleteRule: .nullify, inverse: \AlbumRecord.artist)
    var albums: [AlbumRecord]

    init(
        id: UUID = UUID(),
        name: String,
        isFavorite: Bool = false,
        favoriteDate: Date? = nil,
        trackCount: Int = 0,
        albumCount: Int = 0,
        customArtworkID: UUID? = nil
    ) {
        self.id = id
        sortIdentity = id.uuidString
        self.name = name
        normalizedName = SearchNormalizer.normalize(name)
        self.isFavorite = isFavorite
        self.favoriteDate = favoriteDate
        self.trackCount = trackCount
        self.albumCount = albumCount
        self.customArtworkID = customArtworkID
        tracks = []
        albums = []
    }

    func rename(to name: String) {
        self.name = name
        normalizedName = SearchNormalizer.normalize(name)
    }
}
