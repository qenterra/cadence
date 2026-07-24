@testable import Cadence
import Testing

struct TagEditingSelectionTests {
    private let trackOrder: [TagAssignmentTarget] = [
        .track(1),
        .track(2),
        .track(3),
        .track(4),
    ]

    @Test("Replace and toggle selection follow native list behavior")
    func replaceAndToggle() {
        var selection = TagEditingSelection()

        selection.apply(.replace, target: .track(2), canonicalOrder: trackOrder)
        #expect(selection.targets == [.track(2)])
        #expect(selection.primaryTarget == .track(2))
        #expect(selection.anchor == .track(2))

        selection.apply(.toggle, target: .track(4), canonicalOrder: trackOrder)
        #expect(selection.targets == [.track(2), .track(4)])
        #expect(selection.primaryTarget == .track(4))

        selection.apply(.toggle, target: .track(2), canonicalOrder: trackOrder)
        #expect(selection.targets == [.track(4)])
        #expect(selection.primaryTarget == .track(4))
    }

    @Test("Shift selects the canonical range from the anchor")
    func rangeSelection() {
        var selection = TagEditingSelection()

        selection.apply(.replace, target: .track(2), canonicalOrder: trackOrder)
        selection.apply(.range, target: .track(4), canonicalOrder: trackOrder)

        #expect(selection.targets == [.track(2), .track(3), .track(4)])
        #expect(selection.primaryTarget == .track(4))
        #expect(selection.anchor == .track(2))
    }

    @Test("Canonical order controls selection order instead of click order")
    func canonicalOrdering() {
        var selection = TagEditingSelection()

        selection.apply(.replace, target: .track(4), canonicalOrder: trackOrder)
        selection.apply(.toggle, target: .track(1), canonicalOrder: trackOrder)

        #expect(selection.targets == [.track(1), .track(4)])
    }

    @Test("Track and album targets cannot mix")
    func targetKindIsolation() {
        var selection = TagEditingSelection()

        selection.apply(.replace, target: .track(1), canonicalOrder: trackOrder)
        selection.apply(
            .toggle,
            target: .album("North Assembly\u{1F}Signals After Dark"),
            canonicalOrder: [.album("North Assembly\u{1F}Signals After Dark")]
        )

        #expect(selection.targets == [.album("North Assembly\u{1F}Signals After Dark")])
        #expect(selection.kind == .albums)
    }

    @Test("Pruning removes stale IDs and repairs primary state")
    func pruning() {
        var selection = TagEditingSelection()
        selection.apply(.replace, target: .track(1), canonicalOrder: trackOrder)
        selection.apply(.toggle, target: .track(3), canonicalOrder: trackOrder)

        selection.prune(validTargets: [.track(1)])

        #expect(selection.targets == [.track(1)])
        #expect(selection.primaryTarget == .track(1))
        #expect(selection.anchor == .track(1))
    }

    @Test("Select All uses canonical order and preserves a valid primary target")
    func selectAll() {
        var selection = TagEditingSelection()
        selection.apply(.replace, target: .track(3), canonicalOrder: trackOrder)

        selection.selectAll(canonicalOrder: trackOrder)

        #expect(selection.targets == trackOrder)
        #expect(selection.primaryTarget == .track(3))
        #expect(selection.anchor == .track(3))

        selection.clear()
        selection.selectAll(canonicalOrder: trackOrder)

        #expect(selection.primaryTarget == .track(1))
        #expect(selection.anchor == .track(1))
    }

    @Test("Clear resets selection and its range anchor")
    func clearing() {
        var selection = TagEditingSelection()
        selection.apply(.replace, target: .track(2), canonicalOrder: trackOrder)

        selection.clear()

        #expect(selection.isEmpty)
        #expect(selection.kind == nil)
        #expect(selection.primaryTarget == nil)
        #expect(selection.anchor == nil)
    }
}
