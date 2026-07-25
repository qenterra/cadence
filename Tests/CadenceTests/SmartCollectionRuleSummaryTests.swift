@testable import Cadence
import Foundation
import Testing

struct SmartCollectionRuleSummaryTests {
    @Test("Summary describes tag scope and negation")
    func tagScopeAndNegation() throws {
        let tag = try #require(TagPreview(path: "genre/ambient"))
        let condition = SmartCollectionRuleCondition(
            id: testID(1),
            field: .tag,
            operator: .is,
            value: .tag(id: tag.id, scope: .includeSubtags),
            isNegated: true
        )
        let root = SmartCollectionRuleGroup(
            id: testID(2),
            combinator: .all,
            children: [.condition(condition)]
        )

        let rows = SmartCollectionRuleSummary.rows(
            for: root,
            tags: [tag]
        )

        #expect(rows.count == 2)
        #expect(rows[0].text == "Match all of the following")
        #expect(
            rows[1].text
                == "Not Tag is Genre / Ambient, including subtags"
        )
        #expect(rows[1].depth == 1)
    }

    @Test("Nested groups preserve hierarchy and readable ranges")
    func nestedHierarchy() {
        let range = SmartCollectionRuleCondition(
            id: testID(10),
            field: .rating,
            operator: .between,
            value: .integerRange(lower: 3, upper: 5)
        )
        let nested = SmartCollectionRuleGroup(
            id: testID(11),
            combinator: .any,
            children: [.condition(range)]
        )
        let root = SmartCollectionRuleGroup(
            id: testID(12),
            combinator: .all,
            children: [.group(nested)]
        )

        let rows = SmartCollectionRuleSummary.rows(for: root, tags: [])

        #expect(rows.map(\.depth) == [0, 1, 2])
        #expect(rows[1].text == "Match any of the following")
        #expect(rows[2].text == "Rating between 3–5")
    }

    @Test("Empty groups remain explicit")
    func emptyGroup() {
        let root = SmartCollectionRuleGroup(
            id: testID(20),
            combinator: .all,
            children: []
        )

        let rows = SmartCollectionRuleSummary.rows(for: root, tags: [])

        #expect(rows.count == 1)
        #expect(rows[0].detail == "No rules — matches every track")
    }

    private func testID(_ value: UInt32) -> UUID {
        UUID(
            uuidString: String(
                format: "CA400000-0000-0000-0000-%012X",
                value
            )
        ) ?? UUID()
    }
}
