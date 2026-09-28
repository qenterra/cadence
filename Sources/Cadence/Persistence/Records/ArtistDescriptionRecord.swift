import Foundation
import SwiftData

@Model
final class ArtistDescriptionRecord {
    @Attribute(.unique) var artistID: UUID
    var userDescription: String

    init(artistID: UUID, userDescription: String) {
        self.artistID = artistID
        self.userDescription = userDescription
    }
}
