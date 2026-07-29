@testable import Cadence
import Foundation
import Testing

struct PlaybackQueueStateTests {
    @Test("Completion stops at the end unless repeat all is requested")
    func boundedTraversal() {
        let ids = [UUID(), UUID(), UUID()]
        var queue = PlaybackQueueState(
            source: .adHoc,
            orderedTrackIDs: ids,
            startingAt: ids.last
        )

        #expect(queue.move(by: 1, wrapping: false) == nil)
        #expect(queue.currentTrackID == ids.last)
        #expect(queue.move(by: 1, wrapping: true) == ids.first)
    }

    @Test("Queue edits remain confined to Up Next")
    func edits() {
        let ids = (0 ..< 5).map { _ in UUID() }
        var queue = PlaybackQueueState(
            source: .adHoc,
            orderedTrackIDs: ids,
            startingAt: ids[1]
        )

        let didReorder = queue.reorderUpNext([ids[4]], before: ids[2])
        #expect(didReorder)
        #expect(queue.orderedTrackIDs == [
            ids[0],
            ids[1],
            ids[4],
            ids[2],
            ids[3],
        ])
        let didRemoveFixedRows = queue.removeUpNext([ids[0], ids[1]])
        #expect(!didRemoveFixedRows)
        #expect(queue.currentTrackID == ids[1])
    }

    @Test("Selecting any queue row preserves order and repartitions history")
    func selectingQueueRow() {
        let ids = (0 ..< 5).map { _ in UUID() }
        var queue = PlaybackQueueState(
            source: .adHoc,
            orderedTrackIDs: ids,
            startingAt: ids[1]
        )

        let didMove = queue.move(to: ids[3])
        #expect(didMove)
        #expect(queue.orderedTrackIDs == ids)
        #expect(queue.previouslyPlayedTrackIDs == Array(ids.prefix(3)))
        #expect(queue.currentTrackID == ids[3])
        #expect(queue.upNextTrackIDs == [ids[4]])
        let didMoveMissingTrack = queue.move(to: UUID())
        #expect(!didMoveMissingTrack)
        #expect(queue.currentTrackID == ids[3])
    }
}
