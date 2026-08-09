import Foundation

struct SmartCollectionPreview: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var rule: SmartCollectionRuleGroup
    var modifiedAt: Date
    var customArtworkID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        rule: SmartCollectionRuleGroup,
        modifiedAt: Date,
        customArtworkID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.rule = rule
        self.modifiedAt = modifiedAt
        self.customArtworkID = customArtworkID
    }
}

enum SmartCollectionTransitionTarget: Hashable, Sendable {
    case collection(SmartCollectionPreview.ID)
    case new(draftID: UUID, rootID: UUID)
    case listening
    case rename(SmartCollectionPreview.ID)
    case destination(NavigationDestination)
    case contextualRoute(ContextualMediaRoute)
}

enum SmartCollectionSwitchResolution: Hashable, Sendable {
    case save
    case discard
    case cancel
}

struct SmartCollectionListItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let matchCount: Int
    let totalDuration: TimeInterval
    let isTransient: Bool
    let isSelected: Bool
}
