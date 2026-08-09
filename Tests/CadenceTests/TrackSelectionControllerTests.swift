@testable import Cadence
import Foundation
import Testing

@MainActor
struct TrackSelectionControllerTests {
    @Test("Selection survives sorting but clears between destinations")
    func sortPreservesSelectionAndContextClearsIt() {
        let first = UUID()
        let second = UUID()
        let album = UUID()
        let selection = TrackSelectionController()

        selection.activate(context: .library)
        selection.replace(with: [first, second], anchor: first)
        selection.updateSort(
            TrackTableSortDescriptor(field: .year, direction: .descending)
        )
        #expect(selection.selectedIDs == [first, second])

        selection.activate(context: .album(album))
        #expect(selection.selectedIDs.isEmpty)
        #expect(selection.anchorID == nil)
    }

    @Test("Command and Shift selection use stable track IDs")
    func additiveAndRangeSelection() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        let selection = TrackSelectionController()
        selection.activate(context: .library)

        selection.selectOnly(ids[1])
        selection.toggle(ids[3])
        #expect(selection.selectedIDs == [ids[1], ids[3]])

        selection.selectRange(to: ids[2], orderedIDs: ids)
        #expect(selection.selectedIDs == [ids[1], ids[2]])
    }

    @Test("Pruning keeps only IDs that remain in the result")
    func pruningRemovesStaleIDs() {
        let ids = [UUID(), UUID(), UUID()]
        let selection = TrackSelectionController()
        selection.activate(context: .search("ambient"))
        selection.replace(with: Set(ids), anchor: ids[1])

        selection.prune(to: [ids[0], ids[2]])

        #expect(selection.selectedIDs == [ids[0], ids[2]])
        #expect(selection.anchorID == ids[0])
    }
}
