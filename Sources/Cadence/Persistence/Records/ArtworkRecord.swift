import Foundation
import SwiftData

@Model
final class ArtworkRecord {
    #Index<ArtworkRecord>([\.ownerID], [\.contentHash])

    @Attribute(.unique) var id: UUID
    var ownerKindRawValue: String
    var ownerID: UUID
    var relativeOriginalPath: String
    var relativeThumbnailPath: String?
    var format: String
    var pixelWidth: Int
    var pixelHeight: Int
    var cropScale: Double
    var normalizedOffsetX: Double
    var normalizedOffsetY: Double
    var contentHash: String
    var revision: Int

    init(
        id: UUID = UUID(),
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID,
        relativeOriginalPath: String,
        relativeThumbnailPath: String? = nil,
        format: String,
        pixelWidth: Int,
        pixelHeight: Int,
        cropScale: Double = 1,
        normalizedOffsetX: Double = 0,
        normalizedOffsetY: Double = 0,
        contentHash: String,
        revision: Int = 0
    ) {
        self.id = id
        ownerKindRawValue = ownerKind.rawValue
        self.ownerID = ownerID
        self.relativeOriginalPath = relativeOriginalPath
        self.relativeThumbnailPath = relativeThumbnailPath
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.cropScale = cropScale
        self.normalizedOffsetX = normalizedOffsetX
        self.normalizedOffsetY = normalizedOffsetY
        self.contentHash = contentHash
        self.revision = revision
    }

    var ownerKind: ArtworkOwnerKind {
        get {
            ArtworkOwnerKind(rawValue: ownerKindRawValue) ?? .track
        }
        set {
            ownerKindRawValue = newValue.rawValue
        }
    }
}

enum ArtworkOwnerKind: String, Codable, Sendable {
    case artist
    case album
    case track
}
