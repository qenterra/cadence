import Foundation

struct SmartCollectionDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceID: SmartCollectionPreview.ID?
    var name: String
    var userDescription: String?
    var rule: SmartCollectionRuleGroup

    init(
        id: UUID = UUID(),
        sourceID: SmartCollectionPreview.ID?,
        name: String,
        userDescription: String? = nil,
        rule: SmartCollectionRuleGroup
    ) {
        self.id = id
        self.sourceID = sourceID
        self.name = name
        self.userDescription = userDescription
        self.rule = rule
    }

    init(collection: SmartCollectionPreview) {
        id = collection.id
        sourceID = collection.id
        name = collection.name
        userDescription = collection.userDescription
        rule = collection.rule
    }

    func isDirty(comparedTo collection: SmartCollectionPreview?) -> Bool {
        guard let collection else {
            return true
        }
        return name != collection.name
            || CatalogDescriptionPolicy.normalized(userDescription)
            != CatalogDescriptionPolicy.normalized(collection.userDescription)
            || rule != collection.rule
    }
}
