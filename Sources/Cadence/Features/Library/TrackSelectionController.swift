import Foundation
import Observation

@MainActor
@Observable
final class TrackSelectionController {
    private(set) var selectedIDs: Set<UUID> = []
    private(set) var anchorID: UUID?
    private(set) var context: TrackTableContext?
    private(set) var sort: TrackTableSortDescriptor?

    func activate(context: TrackTableContext) {
        guard context != self.context else {
            return
        }
        self.context = context
        clear()
    }

    func updateSort(_ sort: TrackTableSortDescriptor) {
        self.sort = sort
    }

    func replace(
        with ids: Set<UUID>,
        anchor: UUID?
    ) {
        selectedIDs = ids
        anchorID = anchor.flatMap(ids.contains) == true
            ? anchor
            : ids.first
    }

    func selectOnly(_ id: UUID) {
        selectedIDs = [id]
        anchorID = id
    }

    func toggle(_ id: UUID) {
        if selectedIDs.remove(id) == nil {
            selectedIDs.insert(id)
            if anchorID == nil {
                anchorID = id
            }
        } else if anchorID == id {
            anchorID = selectedIDs.first
        }
    }

    func selectRange(
        to id: UUID,
        orderedIDs: [UUID]
    ) {
        guard let targetIndex = orderedIDs.firstIndex(of: id) else {
            return
        }
        guard
            let anchorID,
            let anchorIndex = orderedIDs.firstIndex(of: anchorID)
        else {
            selectOnly(id)
            return
        }
        let bounds = min(anchorIndex, targetIndex) ... max(
            anchorIndex,
            targetIndex
        )
        selectedIDs = Set(orderedIDs[bounds])
    }

    func prune(to orderedIDs: [UUID]) {
        selectedIDs.formIntersection(orderedIDs)
        if anchorID.map(selectedIDs.contains) != true {
            anchorID = orderedIDs.first(where: selectedIDs.contains)
        }
    }

    func clear() {
        selectedIDs = []
        anchorID = nil
    }
}
