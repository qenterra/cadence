import Foundation

enum SmartCollectionRuleCombinator: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case any

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .all: "All"
        case .any: "Any"
        }
    }
}

enum SmartCollectionRuleField: String, CaseIterable, Identifiable, Hashable, Sendable {
    case tag
    case artist
    case album
    case year
    case format
    case rating
    case favorite

    var id: Self {
        self
    }

    var title: String {
        rawValue.localizedCapitalized
    }

    static var productionCases: [Self] {
        allCases.filter { $0 != .rating }
    }

    var allowedOperators: [SmartCollectionRuleOperator] {
        switch self {
        case .tag, .favorite:
            [.is]
        case .artist, .album, .format:
            [.is, .contains]
        case .year, .rating:
            [.is, .greaterThan, .lessThan, .between]
        }
    }
}

enum SmartCollectionRuleOperator: String, CaseIterable, Identifiable, Hashable, Sendable {
    case `is`
    case contains
    case greaterThan
    case lessThan
    case between

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .is: "is"
        case .contains: "contains"
        case .greaterThan: "greater than"
        case .lessThan: "less than"
        case .between: "between"
        }
    }
}

enum SmartCollectionTagScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case exact
    case includeSubtags

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .exact: "Exact"
        case .includeSubtags: "Include Subtags"
        }
    }
}

enum SmartCollectionRuleValue: Hashable, Sendable {
    case tag(id: TagPreview.ID?, scope: SmartCollectionTagScope)
    case text(String)
    case integer(Int?)
    case integerRange(lower: Int?, upper: Int?)
    case boolean(Bool)
}

struct SmartCollectionRuleCondition: Identifiable, Hashable, Sendable {
    let id: UUID
    var field: SmartCollectionRuleField
    var `operator`: SmartCollectionRuleOperator
    var value: SmartCollectionRuleValue
    var isNegated: Bool

    init(
        id: UUID = UUID(),
        field: SmartCollectionRuleField,
        operator: SmartCollectionRuleOperator,
        value: SmartCollectionRuleValue,
        isNegated: Bool = false
    ) {
        self.id = id
        self.field = field
        self.operator = `operator`
        self.value = value
        self.isNegated = isNegated
    }
}

struct SmartCollectionRuleGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    var combinator: SmartCollectionRuleCombinator
    var children: [SmartCollectionRuleNode]

    init(
        id: UUID = UUID(),
        combinator: SmartCollectionRuleCombinator,
        children: [SmartCollectionRuleNode]
    ) {
        self.id = id
        self.combinator = combinator
        self.children = children
    }
}

indirect enum SmartCollectionRuleNode: Identifiable, Hashable, Sendable {
    case condition(SmartCollectionRuleCondition)
    case group(SmartCollectionRuleGroup)

    var id: UUID {
        switch self {
        case let .condition(condition):
            condition.id
        case let .group(group):
            group.id
        }
    }
}

struct SmartCollectionRuleOptions: Hashable, Sendable {
    let tagIDs: [TagPreview.ID]
    let artists: [String]
    let albums: [String]
    let years: [Int]
    let formats: [String]

    static let empty = SmartCollectionRuleOptions(
        tagIDs: [],
        artists: [],
        albums: [],
        years: [],
        formats: []
    )

    func defaultCondition(
        field: SmartCollectionRuleField = .tag,
        id: UUID = UUID()
    ) -> SmartCollectionRuleCondition {
        let value: SmartCollectionRuleValue = switch field {
        case .tag:
            .tag(id: tagIDs.first, scope: .exact)
        case .artist:
            .text(artists.first ?? "")
        case .album:
            .text(albums.first ?? "")
        case .year:
            .integer(years.first)
        case .format:
            .text(formats.first ?? "")
        case .rating:
            .integer(5)
        case .favorite:
            .boolean(true)
        }

        return SmartCollectionRuleCondition(
            id: id,
            field: field,
            operator: field.allowedOperators[0],
            value: value
        )
    }

    func replacingField(
        of condition: SmartCollectionRuleCondition,
        with field: SmartCollectionRuleField
    ) -> SmartCollectionRuleCondition {
        var replacement = defaultCondition(field: field, id: condition.id)
        replacement.isNegated = condition.isNegated
        return replacement
    }
}
