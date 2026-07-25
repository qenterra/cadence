import Foundation

struct SmartCollectionRuleSummaryRow: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case group
        case condition
    }

    let id: UUID
    let depth: Int
    let kind: Kind
    let text: String
    let detail: String?
}

enum SmartCollectionRuleSummary {
    static func rows(
        for root: SmartCollectionRuleGroup,
        tags: [TagPreview]
    ) -> [SmartCollectionRuleSummaryRow] {
        var result: [SmartCollectionRuleSummaryRow] = [
            groupRow(root, depth: 0),
        ]
        append(
            root.children,
            depth: 1,
            tagsByID: Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) }),
            to: &result
        )
        return result
    }

    private static func append(
        _ nodes: [SmartCollectionRuleNode],
        depth: Int,
        tagsByID: [TagPreview.ID: TagPreview],
        to result: inout [SmartCollectionRuleSummaryRow]
    ) {
        for node in nodes {
            switch node {
            case let .condition(condition):
                result.append(
                    SmartCollectionRuleSummaryRow(
                        id: condition.id,
                        depth: depth,
                        kind: .condition,
                        text: conditionText(
                            condition,
                            tagsByID: tagsByID
                        ),
                        detail: nil
                    )
                )
            case let .group(group):
                result.append(groupRow(group, depth: depth))
                append(
                    group.children,
                    depth: depth + 1,
                    tagsByID: tagsByID,
                    to: &result
                )
            }
        }
    }

    private static func groupRow(
        _ group: SmartCollectionRuleGroup,
        depth: Int
    ) -> SmartCollectionRuleSummaryRow {
        SmartCollectionRuleSummaryRow(
            id: group.id,
            depth: depth,
            kind: .group,
            text: "Match \(group.combinator.title.lowercased()) of the following",
            detail: group.children.isEmpty
                ? "No rules — matches every track"
                : nil
        )
    }

    private static func conditionText(
        _ condition: SmartCollectionRuleCondition,
        tagsByID: [TagPreview.ID: TagPreview]
    ) -> String {
        let prefix = condition.isNegated ? "Not " : ""
        let value = valueText(condition.value, tagsByID: tagsByID)
        return "\(prefix)\(condition.field.title) "
            + "\(condition.operator.title) \(value)"
    }

    private static func valueText(
        _ value: SmartCollectionRuleValue,
        tagsByID: [TagPreview.ID: TagPreview]
    ) -> String {
        switch value {
        case let .tag(id, scope):
            let name = id.flatMap { tagsByID[$0]?.displayPath }
                ?? id
                ?? "Unselected tag"
            return scope == .includeSubtags
                ? "\(name), including subtags"
                : name
        case let .text(text):
            return text.isEmpty ? "Any value" : text
        case let .integer(number):
            return number.map(String.init) ?? "Any value"
        case let .integerRange(lower, upper):
            return "\(lower.map(String.init) ?? "…")"
                + "–\(upper.map(String.init) ?? "…")"
        case let .boolean(value):
            return value ? "Yes" : "No"
        }
    }
}
