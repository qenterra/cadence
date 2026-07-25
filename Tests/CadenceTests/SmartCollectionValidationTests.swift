@testable import Cadence
import Foundation
import Testing

struct SmartCollectionValidationTests {
    @Test("Names are trimmed, required, and unique excluding the draft source")
    func nameValidation() {
        let source = collection(id: smartCollectionTestID(1), name: "Night Music")
        let other = collection(id: smartCollectionTestID(2), name: "Quiet Focus")

        let empty = SmartCollectionDraft(
            id: smartCollectionTestID(3),
            sourceID: nil,
            name: "   ",
            rule: emptyRoot()
        )
        let duplicate = SmartCollectionDraft(
            id: smartCollectionTestID(4),
            sourceID: source.id,
            name: " quiet FOCUS ",
            rule: emptyRoot()
        )
        let unchanged = SmartCollectionDraft(
            id: source.id,
            sourceID: source.id,
            name: " night music ",
            rule: source.rule
        )

        #expect(
            SmartCollectionValidator.validate(
                draft: empty,
                savedCollections: [source, other]
            ).nameIssue?.kind == .emptyName
        )
        #expect(
            SmartCollectionValidator.validate(
                draft: duplicate,
                savedCollections: [source, other]
            ).nameIssue?.kind == .duplicateName
        )
        #expect(
            SmartCollectionValidator.validate(
                draft: unchanged,
                savedCollections: [source, other]
            ).isValid
        )
    }

    @Test("Validation keeps condition failures attached to stable node IDs")
    func conditionValidation() {
        let missingTagID = smartCollectionTestID(10)
        let wrongValueID = smartCollectionTestID(11)
        let root = SmartCollectionRuleGroup(
            id: smartCollectionTestID(12),
            combinator: .all,
            children: [
                .condition(
                    SmartCollectionRuleCondition(
                        id: missingTagID,
                        field: .tag,
                        operator: .is,
                        value: .tag(id: nil, scope: .exact)
                    )
                ),
                .condition(
                    SmartCollectionRuleCondition(
                        id: wrongValueID,
                        field: .favorite,
                        operator: .is,
                        value: .text("yes")
                    )
                ),
            ]
        )
        let draft = SmartCollectionDraft(
            id: smartCollectionTestID(13),
            sourceID: nil,
            name: "Broken",
            rule: root
        )

        let result = SmartCollectionValidator.validate(
            draft: draft,
            savedCollections: []
        )

        #expect(result.issue(for: missingTagID)?.kind == .missingValue)
        #expect(result.issue(for: wrongValueID)?.kind == .incompatibleValue)
        #expect(!result.isValid)
    }

    @Test("Numeric validation enforces ranges, ratings, and four-digit years")
    func numericValidation() {
        let reversedID = smartCollectionTestID(20)
        let ratingID = smartCollectionTestID(21)
        let yearID = smartCollectionTestID(22)
        let root = SmartCollectionRuleGroup(
            id: smartCollectionTestID(23),
            combinator: .all,
            children: [
                .condition(
                    SmartCollectionRuleCondition(
                        id: reversedID,
                        field: .year,
                        operator: .between,
                        value: .integerRange(lower: 2026, upper: 2024)
                    )
                ),
                .condition(
                    SmartCollectionRuleCondition(
                        id: ratingID,
                        field: .rating,
                        operator: .is,
                        value: .integer(6)
                    )
                ),
                .condition(
                    SmartCollectionRuleCondition(
                        id: yearID,
                        field: .year,
                        operator: .is,
                        value: .integer(24)
                    )
                ),
            ]
        )
        let result = SmartCollectionValidator.validate(
            draft: SmartCollectionDraft(
                id: smartCollectionTestID(24),
                sourceID: nil,
                name: "Numeric",
                rule: root
            ),
            savedCollections: []
        )

        #expect(result.issue(for: reversedID)?.kind == .reversedRange)
        #expect(result.issue(for: ratingID)?.kind == .ratingOutOfRange)
        #expect(result.issue(for: yearID)?.kind == .yearOutOfRange)
    }

    @Test("Empty root and valid field values can be saved")
    func validValues() {
        let draft = SmartCollectionDraft(
            id: smartCollectionTestID(30),
            sourceID: nil,
            name: "All Tracks",
            rule: emptyRoot()
        )

        #expect(
            SmartCollectionValidator.validate(
                draft: draft,
                savedCollections: []
            ).isValid
        )
    }

    private func collection(
        id: UUID,
        name: String
    ) -> SmartCollectionPreview {
        SmartCollectionPreview(
            id: id,
            name: name,
            rule: emptyRoot(),
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func emptyRoot() -> SmartCollectionRuleGroup {
        SmartCollectionRuleGroup(
            id: smartCollectionTestID(100),
            combinator: .all,
            children: []
        )
    }
}
