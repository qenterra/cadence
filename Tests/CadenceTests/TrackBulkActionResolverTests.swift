@testable import Cadence
import Foundation
import Testing

struct TrackBulkActionResolverTests {
    @Test("Playlist delete removes references instead of library files")
    func playlistDeleteRemovesReferences() {
        let playlistID = UUID()
        #expect(
            TrackBulkActionResolver.defaultDelete(
                for: .playlist(playlistID)
            ) == .removeFromPlaylist(playlistID)
        )
    }

    @Test("Smart Collections never expose manual membership changes")
    func smartCollectionMembershipIsDerived() {
        let actions = TrackBulkActionResolver.actions(
            for: .smartCollection(UUID())
        )
        #expect(
            !actions.contains { action in
                action.changesSmartCollectionMembership
            }
        )
        #expect(actions.contains(.moveToTrash))
    }

    @Test("Selected track order follows the visible queue")
    func selectedOrderIsStable() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        #expect(
            TrackBulkActionResolver.orderedSelection(
                selectedIDs: [ids[3], ids[1]],
                visibleOrder: ids
            ) == [ids[1], ids[3]]
        )
    }
}
