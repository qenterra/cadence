import Foundation

struct SmartCollectionRuleRow: Identifiable, Hashable, Sendable {
    let id: UUID
    let parentGroupID: UUID
    let depth: Int
    let node: SmartCollectionRuleNode
}

struct SmartCollectionRuleTree: Hashable, Sendable {
    var root: SmartCollectionRuleGroup

    var rows: [SmartCollectionRuleRow] {
        flattenedRows(in: root, depth: 0)
    }

    mutating func setCombinator(
        _ combinator: SmartCollectionRuleCombinator,
        for groupID: UUID
    ) -> Bool {
        updateGroup(id: groupID) {
            $0.combinator = combinator
        }
    }

    mutating func addCondition(
        _ condition: SmartCollectionRuleCondition,
        to groupID: UUID
    ) -> Bool {
        updateGroup(id: groupID) {
            $0.children.append(.condition(condition))
        }
    }

    mutating func addGroup(
        _ group: SmartCollectionRuleGroup,
        to parentGroupID: UUID
    ) -> Bool {
        updateGroup(id: parentGroupID) {
            $0.children.append(.group(group))
        }
    }

    mutating func updateCondition(
        id conditionID: UUID,
        _ mutation: (inout SmartCollectionRuleCondition) -> Void
    ) -> Bool {
        root.updateCondition(id: conditionID, mutation)
    }

    mutating func removeNode(id nodeID: UUID) -> Bool {
        root.removeNode(id: nodeID)
    }

    func condition(id conditionID: UUID) -> SmartCollectionRuleCondition? {
        root.condition(id: conditionID)
    }

    private mutating func updateGroup(
        id groupID: UUID,
        _ mutation: (inout SmartCollectionRuleGroup) -> Void
    ) -> Bool {
        if root.id == groupID {
            mutation(&root)
            return true
        }
        return root.updateGroup(id: groupID, mutation)
    }

    private func flattenedRows(
        in group: SmartCollectionRuleGroup,
        depth: Int
    ) -> [SmartCollectionRuleRow] {
        group.children.flatMap { node -> [SmartCollectionRuleRow] in
            let row = SmartCollectionRuleRow(
                id: node.id,
                parentGroupID: group.id,
                depth: depth,
                node: node
            )
            guard case let .group(nestedGroup) = node else {
                return [row]
            }
            return [row] + flattenedRows(
                in: nestedGroup,
                depth: depth + 1
            )
        }
    }
}

private extension SmartCollectionRuleGroup {
    mutating func updateGroup(
        id groupID: UUID,
        _ mutation: (inout SmartCollectionRuleGroup) -> Void
    ) -> Bool {
        for index in children.indices {
            guard case var .group(group) = children[index] else {
                continue
            }
            if group.id == groupID {
                mutation(&group)
                children[index] = .group(group)
                return true
            }
            if group.updateGroup(id: groupID, mutation) {
                children[index] = .group(group)
                return true
            }
        }
        return false
    }

    mutating func updateCondition(
        id conditionID: UUID,
        _ mutation: (inout SmartCollectionRuleCondition) -> Void
    ) -> Bool {
        for index in children.indices {
            switch children[index] {
            case var .condition(condition):
                guard condition.id == conditionID else {
                    continue
                }
                mutation(&condition)
                children[index] = .condition(condition)
                return true
            case var .group(group):
                if group.updateCondition(id: conditionID, mutation) {
                    children[index] = .group(group)
                    return true
                }
            }
        }
        return false
    }

    mutating func removeNode(id nodeID: UUID) -> Bool {
        for index in children.indices {
            if children[index].id == nodeID {
                children.remove(at: index)
                return true
            }
            guard case var .group(group) = children[index] else {
                continue
            }
            if group.removeNode(id: nodeID) {
                if group.children.isEmpty {
                    children.remove(at: index)
                } else {
                    children[index] = .group(group)
                }
                return true
            }
        }
        return false
    }

    func condition(id conditionID: UUID) -> SmartCollectionRuleCondition? {
        for child in children {
            switch child {
            case let .condition(condition) where condition.id == conditionID:
                return condition
            case let .group(group):
                if let condition = group.condition(id: conditionID) {
                    return condition
                }
            default:
                continue
            }
        }
        return nil
    }
}
