import AppKit

struct TrackTableSelectionModifiers: Equatable, Sendable {
    let isRange: Bool
    let isAdditive: Bool

    init(_ flags: NSEvent.ModifierFlags) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        isRange = flags.contains(.shift)
        isAdditive = flags.contains(.command) || flags.contains(.control)
    }
}

enum TrackTableContextSelection {
    static func resolve(
        clickedRow: Int,
        selectedRows: IndexSet,
        modifiers: TrackTableSelectionModifiers
    ) -> IndexSet {
        if modifiers.isAdditive {
            var result = selectedRows
            result.formSymmetricDifference(IndexSet(integer: clickedRow))
            return result
        }
        return selectedRows.contains(clickedRow)
            ? selectedRows
            : IndexSet(integer: clickedRow)
    }
}
