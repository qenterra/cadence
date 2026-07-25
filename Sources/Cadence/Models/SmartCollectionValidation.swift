import Foundation

enum SmartCollectionValidationIssueKind: Hashable, Sendable {
    case emptyName
    case duplicateName
    case missingValue
    case incompatibleOperator
    case incompatibleValue
    case reversedRange
    case ratingOutOfRange
    case yearOutOfRange

    var message: String {
        switch self {
        case .emptyName: "Enter a collection name."
        case .duplicateName: "A collection with this name already exists."
        case .missingValue: "Choose or enter a value."
        case .incompatibleOperator: "This operator does not work with the selected field."
        case .incompatibleValue: "This value does not work with the selected field."
        case .reversedRange: "The first value must not exceed the second."
        case .ratingOutOfRange: "Rating must be between 0 and 5."
        case .yearOutOfRange: "Enter a four-digit year."
        }
    }
}

enum SmartCollectionValidationLocation: Hashable, Sendable {
    case name
    case condition(UUID)
}

struct SmartCollectionValidationIssue: Identifiable, Hashable, Sendable {
    let location: SmartCollectionValidationLocation
    let kind: SmartCollectionValidationIssueKind

    var id: SmartCollectionValidationLocation {
        location
    }

    var message: String {
        kind.message
    }
}

struct SmartCollectionValidationResult: Hashable, Sendable {
    let issues: [SmartCollectionValidationIssue]

    var isValid: Bool {
        issues.isEmpty
    }

    var nameIssue: SmartCollectionValidationIssue? {
        issues.first { $0.location == .name }
    }

    func issue(for conditionID: UUID) -> SmartCollectionValidationIssue? {
        issues.first { $0.location == .condition(conditionID) }
    }
}

enum SmartCollectionValidator {
    static func validate(
        draft: SmartCollectionDraft,
        savedCollections: [SmartCollectionPreview]
    ) -> SmartCollectionValidationResult {
        var issues: [SmartCollectionValidationIssue] = []
        let trimmedName = draft.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if trimmedName.isEmpty {
            issues.append(issue(.emptyName, at: .name))
        } else if savedCollections.contains(where: {
            $0.id != draft.sourceID
                && normalized($0.name) == normalized(trimmedName)
        }) {
            issues.append(issue(.duplicateName, at: .name))
        }

        appendConditionIssues(in: draft.rule, to: &issues)
        return SmartCollectionValidationResult(issues: issues)
    }

    private static func appendConditionIssues(
        in group: SmartCollectionRuleGroup,
        to issues: inout [SmartCollectionValidationIssue]
    ) {
        for child in group.children {
            switch child {
            case let .condition(condition):
                if let kind = conditionIssue(condition) {
                    issues.append(
                        issue(kind, at: .condition(condition.id))
                    )
                }
            case let .group(nestedGroup):
                appendConditionIssues(in: nestedGroup, to: &issues)
            }
        }
    }

    private static func conditionIssue(
        _ condition: SmartCollectionRuleCondition
    ) -> SmartCollectionValidationIssueKind? {
        guard condition.field.allowedOperators.contains(condition.operator) else {
            return .incompatibleOperator
        }

        switch (condition.field, condition.value) {
        case let (.tag, .tag(id, _)):
            return id?.isEmpty == false ? nil : .missingValue
        case let (.artist, .text(value)),
             let (.album, .text(value)),
             let (.format, .text(value)):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .missingValue
                : nil
        case let (.year, .integer(value)):
            return numericIssue(value, field: .year)
        case let (.rating, .integer(value)):
            return numericIssue(value, field: .rating)
        case let (.year, .integerRange(lower, upper)):
            return rangeIssue(lower, upper, field: .year)
        case let (.rating, .integerRange(lower, upper)):
            return rangeIssue(lower, upper, field: .rating)
        case (.favorite, .boolean):
            return nil
        default:
            return .incompatibleValue
        }
    }

    private static func numericIssue(
        _ value: Int?,
        field: SmartCollectionRuleField
    ) -> SmartCollectionValidationIssueKind? {
        guard let value else {
            return .missingValue
        }
        return boundsIssue(value, field: field)
    }

    private static func rangeIssue(
        _ lower: Int?,
        _ upper: Int?,
        field: SmartCollectionRuleField
    ) -> SmartCollectionValidationIssueKind? {
        guard let lower, let upper else {
            return .missingValue
        }
        if lower > upper {
            return .reversedRange
        }
        return boundsIssue(lower, field: field)
            ?? boundsIssue(upper, field: field)
    }

    private static func boundsIssue(
        _ value: Int,
        field: SmartCollectionRuleField
    ) -> SmartCollectionValidationIssueKind? {
        switch field {
        case .rating:
            (0 ... 5).contains(value) ? nil : .ratingOutOfRange
        case .year:
            (1000 ... 9999).contains(value) ? nil : .yearOutOfRange
        default:
            nil
        }
    }

    private static func issue(
        _ kind: SmartCollectionValidationIssueKind,
        at location: SmartCollectionValidationLocation
    ) -> SmartCollectionValidationIssue {
        SmartCollectionValidationIssue(location: location, kind: kind)
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
    }
}
