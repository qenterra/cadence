import Foundation

enum TagEditingTargetKind: Hashable, Sendable {
    case tracks
    case albums
}

enum TagSelectionGesture: Hashable, Sendable {
    case replace
    case toggle
    case range
}

struct TagEditingSelection: Equatable, Sendable {
    private(set) var targets: [TagAssignmentTarget] = []
    private(set) var primaryTarget: TagAssignmentTarget?
    private(set) var anchor: TagAssignmentTarget?

    var kind: TagEditingTargetKind? {
        targets.first?.editingKind
    }

    var isEmpty: Bool {
        targets.isEmpty
    }

    var count: Int {
        targets.count
    }

    func contains(_ target: TagAssignmentTarget) -> Bool {
        targets.contains(target)
    }

    mutating func apply(
        _ gesture: TagSelectionGesture,
        target: TagAssignmentTarget,
        canonicalOrder: [TagAssignmentTarget]
    ) {
        if kind != nil, kind != target.editingKind {
            clear()
        }

        let compatibleOrder = canonicalOrder.filter { $0.editingKind == target.editingKind }
        switch gesture {
        case .replace:
            replace(with: target)
        case .toggle:
            toggle(target)
        case .range:
            extendRange(to: target, canonicalOrder: compatibleOrder)
        }

        sort(using: compatibleOrder)
    }

    mutating func prune(validTargets: [TagAssignmentTarget]) {
        let validTargets = Set(validTargets)
        targets.removeAll { !validTargets.contains($0) }

        guard !targets.isEmpty else {
            clear()
            return
        }

        if primaryTarget.map({ !validTargets.contains($0) }) ?? true {
            primaryTarget = targets.last
        }
        if anchor.map({ !validTargets.contains($0) }) ?? true {
            anchor = targets.first
        }
    }

    mutating func selectAll(
        canonicalOrder: [TagAssignmentTarget]
    ) {
        guard let kind = canonicalOrder.first?.editingKind else {
            clear()
            return
        }

        let compatibleOrder = canonicalOrder.filter {
            $0.editingKind == kind
        }
        let retainedPrimary = primaryTarget.flatMap { primary in
            compatibleOrder.contains(primary) ? primary : nil
        }
        let newPrimary = retainedPrimary ?? compatibleOrder.first

        targets = compatibleOrder
        primaryTarget = newPrimary
        anchor = newPrimary
    }

    mutating func clear() {
        targets = []
        primaryTarget = nil
        anchor = nil
    }

    private mutating func replace(with target: TagAssignmentTarget) {
        targets = [target]
        primaryTarget = target
        anchor = target
    }

    private mutating func toggle(_ target: TagAssignmentTarget) {
        if let index = targets.firstIndex(of: target) {
            targets.remove(at: index)
            if targets.isEmpty {
                clear()
                return
            }
            if primaryTarget == target {
                primaryTarget = targets.last
            }
            if anchor == target {
                anchor = primaryTarget
            }
        } else {
            targets.append(target)
            primaryTarget = target
            anchor = target
        }
    }

    private mutating func extendRange(
        to target: TagAssignmentTarget,
        canonicalOrder: [TagAssignmentTarget]
    ) {
        guard
            let anchor,
            let startIndex = canonicalOrder.firstIndex(of: anchor),
            let endIndex = canonicalOrder.firstIndex(of: target)
        else {
            replace(with: target)
            return
        }

        let range = min(startIndex, endIndex) ... max(startIndex, endIndex)
        targets = Array(canonicalOrder[range])
        primaryTarget = target
    }

    private mutating func sort(using canonicalOrder: [TagAssignmentTarget]) {
        guard !canonicalOrder.isEmpty else {
            return
        }
        let selected = Set(targets)
        let orderedTargets = canonicalOrder.filter(selected.contains)
        let canonicalTargets = Set(canonicalOrder)
        let remainingTargets = targets.filter { !canonicalTargets.contains($0) }
        targets = orderedTargets + remainingTargets
    }
}

extension TagAssignmentTarget {
    var editingKind: TagEditingTargetKind {
        switch self {
        case .track:
            .tracks
        case .album:
            .albums
        }
    }
}
