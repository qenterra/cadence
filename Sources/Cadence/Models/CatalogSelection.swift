import AppKit

enum CatalogActivationKind: Hashable, Sendable {
    case track
    case album
    case artist
    case playlist
    case smartCollection
    case tag
}

struct CatalogActivationTarget: Hashable, Sendable {
    let kind: CatalogActivationKind
    let id: UUID
}

enum CatalogSelectionAction: Equatable, Sendable {
    case selected
    case activate
}

struct CatalogActivationSelection: Equatable, Sendable {
    private(set) var targets: Set<CatalogActivationTarget> = []
    private(set) var primary: CatalogActivationTarget?
    private(set) var anchor: CatalogActivationTarget?

    var selected: CatalogActivationTarget? {
        primary
    }

    func contains(_ target: CatalogActivationTarget) -> Bool {
        targets.contains(target)
    }

    mutating func request(_ target: CatalogActivationTarget) -> Bool {
        handle(
            target,
            orderedTargets: [target],
            modifiers: []
        ) == .activate
    }

    @discardableResult
    mutating func handle(
        _ target: CatalogActivationTarget,
        orderedTargets: [CatalogActivationTarget],
        modifiers: NSEvent.ModifierFlags
    ) -> CatalogSelectionAction {
        let modifiers = modifiers.intersection(
            .deviceIndependentFlagsMask
        )
        let changesKind = primary?.kind != nil
            && primary?.kind != target.kind
        if changesKind {
            replace(with: target)
            let hasSelectionModifier = modifiers.contains(.shift)
                || modifiers.contains(.command)
                || modifiers.contains(.control)
            return hasSelectionModifier ? .selected : .activate
        }

        if modifiers.contains(.shift) {
            selectRange(to: target, orderedTargets: orderedTargets)
            return .selected
        }

        if modifiers.contains(.command) || modifiers.contains(.control) {
            toggle(target, orderedTargets: orderedTargets)
            return .selected
        }

        replace(with: target)
        return .activate
    }

    private mutating func replace(with target: CatalogActivationTarget) {
        targets = [target]
        primary = target
        anchor = target
    }

    private mutating func toggle(
        _ target: CatalogActivationTarget,
        orderedTargets: [CatalogActivationTarget]
    ) {
        if targets.contains(target) {
            targets.remove(target)
            if primary == target {
                primary = firstSelectedTarget(in: orderedTargets)
            }
            if anchor == target {
                anchor = primary
            }
        } else {
            targets.insert(target)
            primary = target
            anchor = anchor ?? target
        }
        if targets.isEmpty {
            primary = nil
            anchor = nil
        }
    }

    private mutating func selectRange(
        to target: CatalogActivationTarget,
        orderedTargets: [CatalogActivationTarget]
    ) {
        guard
            let anchor,
            anchor.kind == target.kind,
            let anchorIndex = orderedTargets.firstIndex(of: anchor),
            let targetIndex = orderedTargets.firstIndex(of: target)
        else {
            replace(with: target)
            return
        }
        let bounds = min(anchorIndex, targetIndex) ... max(
            anchorIndex,
            targetIndex
        )
        targets = Set(orderedTargets[bounds])
        primary = target
    }

    private func firstSelectedTarget(
        in orderedTargets: [CatalogActivationTarget]
    ) -> CatalogActivationTarget? {
        orderedTargets.first(where: targets.contains)
            ?? targets.first
    }
}
