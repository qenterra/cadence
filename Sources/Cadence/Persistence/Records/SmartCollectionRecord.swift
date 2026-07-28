import Foundation
import SwiftData

@Model
final class SmartCollectionRecord {
    #Index<SmartCollectionRecord>([\.normalizedName], [\.modifiedAt])

    @Attribute(.unique) var id: UUID
    var name: String
    var normalizedName: String
    var ruleData: Data
    var sortDescriptorRawValue: String
    var playbackPreferenceRawValue: String
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        ruleData: Data,
        sortDescriptorRawValue: String,
        playbackPreferenceRawValue: String,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        normalizedName = SearchNormalizer.normalize(name)
        self.ruleData = ruleData
        self.sortDescriptorRawValue = sortDescriptorRawValue
        self.playbackPreferenceRawValue = playbackPreferenceRawValue
        self.modifiedAt = modifiedAt
    }

    func rename(to name: String) {
        self.name = name
        normalizedName = SearchNormalizer.normalize(name)
    }
}
