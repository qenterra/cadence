import Foundation

extension CadenceAppModel {
    func setSmartCollectionCombinator(
        _ combinator: SmartCollectionRuleCombinator,
        groupID: UUID
    ) {
        mutateSmartCollectionRuleTree {
            _ = $0.setCombinator(combinator, for: groupID)
        }
    }

    func addSmartCollectionCondition(
        _ condition: SmartCollectionRuleCondition,
        to groupID: UUID
    ) {
        mutateSmartCollectionRuleTree {
            _ = $0.addCondition(condition, to: groupID)
        }
    }

    func addDefaultSmartCollectionCondition(to groupID: UUID) {
        addSmartCollectionCondition(
            smartCollectionRuleOptions.defaultCondition(),
            to: groupID
        )
    }

    func addSmartCollectionGroup(
        to parentGroupID: UUID,
        groupID: UUID = UUID(),
        conditionID: UUID = UUID()
    ) {
        let condition = smartCollectionRuleOptions.defaultCondition(
            id: conditionID
        )
        let group = SmartCollectionRuleGroup(
            id: groupID,
            combinator: .all,
            children: [.condition(condition)]
        )
        mutateSmartCollectionRuleTree {
            _ = $0.addGroup(group, to: parentGroupID)
        }
    }

    func replaceSmartCollectionField(
        _ field: SmartCollectionRuleField,
        conditionID: UUID
    ) {
        let options = smartCollectionRuleOptions
        mutateSmartCollectionCondition(id: conditionID) {
            $0 = options.replacingField(of: $0, with: field)
        }
    }

    func updateSmartCollectionOperator(
        _ newOperator: SmartCollectionRuleOperator,
        conditionID: UUID
    ) {
        mutateSmartCollectionCondition(id: conditionID) { condition in
            condition.operator = newOperator
            condition.value = convertedValue(
                condition.value,
                for: newOperator
            )
        }
    }

    func updateSmartCollectionValue(
        _ value: SmartCollectionRuleValue,
        conditionID: UUID
    ) {
        mutateSmartCollectionCondition(id: conditionID) {
            $0.value = value
        }
    }

    func toggleSmartCollectionNegation(conditionID: UUID) {
        mutateSmartCollectionCondition(id: conditionID) {
            $0.isNegated.toggle()
        }
    }

    func removeSmartCollectionRuleNode(_ nodeID: UUID) {
        mutateSmartCollectionRuleTree {
            _ = $0.removeNode(id: nodeID)
        }
    }

    private func mutateSmartCollectionCondition(
        id conditionID: UUID,
        _ mutation: @escaping (inout SmartCollectionRuleCondition) -> Void
    ) {
        mutateSmartCollectionRuleTree {
            _ = $0.updateCondition(id: conditionID, mutation)
        }
    }

    private func mutateSmartCollectionRuleTree(
        _ mutation: @escaping (inout SmartCollectionRuleTree) -> Void
    ) {
        mutateSmartCollectionDraft { draft in
            var tree = SmartCollectionRuleTree(root: draft.rule)
            mutation(&tree)
            draft.rule = tree.root
        }
    }
}

private func convertedValue(
    _ value: SmartCollectionRuleValue,
    for newOperator: SmartCollectionRuleOperator
) -> SmartCollectionRuleValue {
    switch (newOperator, value) {
    case let (.between, .integer(number)):
        .integerRange(lower: number, upper: number)
    case let (_, .integerRange(lower, _)) where newOperator != .between:
        .integer(lower)
    default:
        value
    }
}
