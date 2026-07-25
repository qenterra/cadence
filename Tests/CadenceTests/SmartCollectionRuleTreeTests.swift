@testable import Cadence
import Foundation
import Testing

struct SmartCollectionRuleTreeTests {
    @Test("Rule tree preserves stable identity and canonical flattened depth")
    func flattenedRows() {
        let rootID = smartCollectionTestID(1)
        let directID = smartCollectionTestID(2)
        let groupID = smartCollectionTestID(3)
        let nestedID = smartCollectionTestID(4)
        let root = SmartCollectionRuleGroup(
            id: rootID,
            combinator: .all,
            children: [
                .condition(textCondition(id: directID)),
                .group(
                    SmartCollectionRuleGroup(
                        id: groupID,
                        combinator: .any,
                        children: [.condition(textCondition(id: nestedID))]
                    )
                ),
            ]
        )

        let rows = SmartCollectionRuleTree(root: root).rows

        #expect(rows.map(\.id) == [directID, groupID, nestedID])
        #expect(rows.map(\.depth) == [0, 0, 1])
        #expect(rows.map(\.parentGroupID) == [rootID, rootID, groupID])
    }

    @Test("Rule tree mutations use IDs instead of unstable indexes")
    func mutations() {
        let rootID = smartCollectionTestID(10)
        let conditionID = smartCollectionTestID(11)
        var tree = SmartCollectionRuleTree(
            root: SmartCollectionRuleGroup(
                id: rootID,
                combinator: .all,
                children: []
            )
        )

        let changedCombinator = tree.setCombinator(.any, for: rootID)
        let addedCondition = tree.addCondition(
            textCondition(id: conditionID),
            to: rootID
        )
        let updatedCondition = tree.updateCondition(id: conditionID) {
            $0.isNegated = true
        }

        #expect(changedCombinator)
        #expect(addedCondition)
        #expect(updatedCondition)
        #expect(tree.root.combinator == .any)
        #expect(tree.condition(id: conditionID)?.isNegated == true)
        let removedCondition = tree.removeNode(id: conditionID)
        #expect(removedCondition)
        #expect(tree.root.children.isEmpty)
    }

    @Test("Removing a nested group's final condition removes the empty group")
    func removesEmptyNestedGroup() {
        let rootID = smartCollectionTestID(20)
        let groupID = smartCollectionTestID(21)
        let conditionID = smartCollectionTestID(22)
        var tree = SmartCollectionRuleTree(
            root: SmartCollectionRuleGroup(
                id: rootID,
                combinator: .all,
                children: [
                    .group(
                        SmartCollectionRuleGroup(
                            id: groupID,
                            combinator: .all,
                            children: [.condition(textCondition(id: conditionID))]
                        )
                    ),
                ]
            )
        )

        let removedCondition = tree.removeNode(id: conditionID)
        #expect(removedCondition)
        #expect(tree.root.children.isEmpty)
    }

    @Test("Adding a group and stale mutations are deterministic")
    func addsGroupAndIgnoresStaleIDs() {
        let rootID = smartCollectionTestID(30)
        let groupID = smartCollectionTestID(31)
        let conditionID = smartCollectionTestID(32)
        var tree = SmartCollectionRuleTree(
            root: SmartCollectionRuleGroup(
                id: rootID,
                combinator: .all,
                children: []
            )
        )
        let group = SmartCollectionRuleGroup(
            id: groupID,
            combinator: .all,
            children: [.condition(textCondition(id: conditionID))]
        )

        let addedGroup = tree.addGroup(group, to: rootID)
        let addedToStaleGroup = tree.addCondition(
            textCondition(id: smartCollectionTestID(33)),
            to: smartCollectionTestID(999)
        )
        let changedStaleGroup = tree.setCombinator(
            .any,
            for: smartCollectionTestID(999)
        )
        let removedStaleNode = tree.removeNode(id: smartCollectionTestID(999))

        #expect(addedGroup)
        #expect(tree.rows.map(\.id) == [groupID, conditionID])
        #expect(!addedToStaleGroup)
        #expect(!changedStaleGroup)
        #expect(!removedStaleNode)
    }

    private func textCondition(id: UUID) -> SmartCollectionRuleCondition {
        SmartCollectionRuleCondition(
            id: id,
            field: .artist,
            operator: .is,
            value: .text("North Assembly")
        )
    }
}

func smartCollectionTestID(_ value: UInt32) -> UUID {
    UUID(
        uuidString: String(
            format: "00000000-0000-0000-0000-%012X",
            value
        )
    ) ?? UUID()
}
