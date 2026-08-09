import Foundation

enum TrackBulkAction: Equatable, Sendable {
    case playNext
    case addToQueue
    case assignTags
    case addToPlaylist
    case moveToTrash
    case removeFromPlaylist(UUID)
    case manualSmartCollectionMembership(UUID)

    var changesSmartCollectionMembership: Bool {
        if case .manualSmartCollectionMembership = self {
            return true
        }
        return false
    }
}

enum TrackBulkActionResolver {
    static func actions(
        for context: TrackTableContext
    ) -> [TrackBulkAction] {
        var result: [TrackBulkAction] = [
            .playNext,
            .addToQueue,
            .assignTags,
            .addToPlaylist,
        ]
        if case let .playlist(playlistID) = context {
            result.append(.removeFromPlaylist(playlistID))
        }
        result.append(.moveToTrash)
        return result
    }

    static func defaultDelete(
        for context: TrackTableContext
    ) -> TrackBulkAction {
        if case let .playlist(playlistID) = context {
            return .removeFromPlaylist(playlistID)
        }
        return .moveToTrash
    }

    static func orderedSelection(
        selectedIDs: Set<UUID>,
        visibleOrder: [UUID]
    ) -> [UUID] {
        visibleOrder.filter(selectedIDs.contains)
    }
}
