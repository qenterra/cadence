import Foundation
import SwiftData

@Model
final class PlaylistRecord {
    #Index<PlaylistRecord>([\.normalizedName], [\.modifiedAt])

    @Attribute(.unique) var id: UUID
    var name: String
    var normalizedName: String
    var createdAt: Date
    var modifiedAt: Date
    var customArtworkID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        customArtworkID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        normalizedName = SearchNormalizer.normalize(name)
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.customArtworkID = customArtworkID
    }

    func rename(
        to name: String
    ) {
        self.name = name
        normalizedName = SearchNormalizer.normalize(name)
        modifiedAt = .now
    }
}
