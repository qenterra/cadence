import Foundation

enum SmartCollectionRuleCombinator: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case all
    case any

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .any: String(localized: "Any")
        }
    }
}

enum SmartCollectionRuleField: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
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
        switch self {
        case .tag: String(localized: "Tag")
        case .artist: String(localized: "Artist")
        case .album: String(localized: "Album")
        case .year: String(localized: "Year")
        case .format: String(localized: "Format")
        case .rating: String(localized: "Rating")
        case .favorite: String(localized: "Favorite")
        }
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

enum SmartCollectionRuleOperator: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
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
        case .is: String(localized: "is")
        case .contains: String(localized: "contains")
        case .greaterThan: String(localized: "greater than")
        case .lessThan: String(localized: "less than")
        case .between: String(localized: "between")
        }
    }
}

enum SmartCollectionTagScope: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case exact
    case includeSubtags

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .exact: String(localized: "Exact")
        case .includeSubtags: String(localized: "Include Subtags")
        }
    }
}

enum SmartCollectionRuleValue: Codable, Hashable, Sendable {
    case tag(id: TagPreview.ID?, scope: SmartCollectionTagScope)
    case text(String)
    case integer(Int?)
    case integerRange(lower: Int?, upper: Int?)
    case boolean(Bool)
}

struct SmartCollectionRuleCondition: Codable, Identifiable, Hashable, Sendable {
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

struct SmartCollectionRuleGroup: Codable, Identifiable, Hashable, Sendable {
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

indirect enum SmartCollectionRuleNode: Codable, Identifiable, Hashable, Sendable {
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
