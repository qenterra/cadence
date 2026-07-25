@testable import Cadence
import Foundation
import Testing

struct PlaybackQueueTests {
    @Test("Queue preserves source, order, start, and shuffle state")
    func queueIdentity() {
        let collectionID = UUID(
            uuidString: "CA100000-0000-0000-0000-000000000001"
        ) ?? UUID()
        let queue = PlaybackQueue(
            source: .smartCollection(collectionID),
            orderedTrackIDs: [3, 1, 2],
            startingAt: 1,
            isShuffled: true
        )

        #expect(queue.source == .smartCollection(collectionID))
        #expect(queue.orderedTrackIDs == [3, 1, 2])
        #expect(queue.currentTrackID == 1)
        #expect(queue.isShuffled)
    }

    @Test("Queue falls back to the first item and removes duplicate IDs")
    func queueNormalization() {
        let queue = PlaybackQueue(
            source: .adHoc,
            orderedTrackIDs: [4, 4, 2, 4],
            startingAt: 99
        )

        #expect(queue.orderedTrackIDs == [4, 2])
        #expect(queue.currentTrackID == 4)
    }

    @Test("Previous and next wrap while skipping stale IDs")
    func traversal() {
        var queue = PlaybackQueue(
            source: .adHoc,
            orderedTrackIDs: [1, 2, 3, 4],
            startingAt: 1
        )

        #expect(queue.move(by: -1, availableTrackIDs: [1, 3]) == 3)
        #expect(queue.move(by: 1, availableTrackIDs: [1, 3]) == 1)
        #expect(queue.move(by: 1, availableTrackIDs: [1, 3]) == 3)
    }

    @Test("Seeded shuffle is deterministic and preserves membership")
    func shuffle() {
        let ids = Array(1 ... 12)
        var firstGenerator = SeededGenerator(seed: 42)
        var secondGenerator = SeededGenerator(seed: 42)

        let first = PlaybackQueue.shuffledOrder(
            ids,
            using: &firstGenerator
        )
        let second = PlaybackQueue.shuffledOrder(
            ids,
            using: &secondGenerator
        )

        #expect(first == second)
        #expect(first != ids)
        #expect(Set(first) == Set(ids))
        #expect(first.count == ids.count)
    }

    @Test("Queue exposes stable history, current, and Up Next sections")
    func sections() {
        let queue = PlaybackQueue(
            source: .adHoc,
            orderedTrackIDs: [1, 2, 3, 4],
            startingAt: 2
        )

        #expect(queue.previouslyPlayedTrackIDs == [1])
        #expect(queue.currentTrackID == 2)
        #expect(queue.upNextTrackIDs == [3, 4])
    }

    @Test("Only Up Next rows can be reordered")
    func reorderUpNext() {
        var queue = PlaybackQueue(
            source: .adHoc,
            orderedTrackIDs: [1, 2, 3, 4, 5],
            startingAt: 2
        )

        let didReorder = queue.reorderUpNext([5, 4], before: 3)
        #expect(didReorder)
        #expect(queue.orderedTrackIDs == [1, 2, 4, 5, 3])
        let didReorderFixedRows = queue.reorderUpNext([1, 2], before: 3)
        #expect(!didReorderFixedRows)
        #expect(queue.currentTrackID == 2)
    }

    @Test("Remove and Clear preserve playback history and the current track")
    func removeAndClear() {
        var queue = PlaybackQueue(
            source: .adHoc,
            orderedTrackIDs: [1, 2, 3, 4],
            startingAt: 2
        )

        let didRemove = queue.removeUpNext([3])
        #expect(didRemove)
        #expect(queue.orderedTrackIDs == [1, 2, 4])
        let didClear = queue.clearUpNext()
        #expect(didClear)
        #expect(queue.orderedTrackIDs == [1, 2])
        #expect(queue.currentTrackID == 2)
    }

    @Test("Play Next moves eligible rows while Add appends new rows")
    func insertions() {
        var queue = PlaybackQueue(
            source: .adHoc,
            orderedTrackIDs: [1, 2, 3, 4],
            startingAt: 2
        )

        let didPlayNext = queue.playNext([4, 5, 2, 4])
        #expect(didPlayNext)
        #expect(queue.orderedTrackIDs == [1, 2, 4, 5, 3])
        let didAdd = queue.addToEnd([6, 3, 1, 6])
        #expect(didAdd)
        #expect(queue.orderedTrackIDs == [1, 2, 4, 5, 3, 6])
        #expect(queue.currentTrackID == 2)
    }
}

@MainActor
struct PlaybackQueueAppModelTests {
    @Test("A model queue starts at selection and drives transport")
    func appModelTraversal() throws {
        let model = CadenceAppModel()
        let tracks = Array(model.tracks.prefix(4))
        let start = try #require(tracks.dropFirst().first)

        let started = model.startPlaybackQueue(
            source: .smartCollection(
                UUID(
                    uuidString: "CA100000-0000-0000-0000-000000000002"
                ) ?? UUID()
            ),
            trackIDs: tracks.map(\.id),
            startingAt: start.id
        )

        #expect(started)
        #expect(model.currentTrackID == start.id)
        #expect(model.selectedTrackID == start.id)
        #expect(model.isPlaying)

        model.selectNextTrack()
        #expect(model.currentTrackID == tracks[2].id)

        model.selectPreviousTrack()
        #expect(model.currentTrackID == start.id)
    }

    @Test("Starting outside the queue falls back to its first track")
    func appModelFallback() throws {
        let model = CadenceAppModel()
        let tracks = Array(model.tracks.suffix(3))
        let first = try #require(tracks.first)

        model.startPlaybackQueue(
            source: .adHoc,
            trackIDs: tracks.map(\.id),
            startingAt: -1
        )

        #expect(model.currentTrackID == first.id)
    }

    @Test("Album Play captures an album queue without changing canonical order")
    func albumQueue() throws {
        let model = CadenceAppModel()
        let track = try #require(model.tracks.dropFirst().first)
        let expectedIDs = model.tracks
            .filter { $0.albumID == track.albumID }
            .map(\.id)

        model.play(track)

        #expect(model.activePlaybackQueue?.source == .album(track.albumID))
        #expect(model.activePlaybackQueue?.orderedTrackIDs == expectedIDs)
        #expect(model.activePlaybackQueue?.currentTrackID == track.id)
    }

    @Test("A queue is a snapshot independent from later source changes")
    func snapshot() throws {
        let model = CadenceAppModel()
        var sourceIDs = Array(model.tracks.prefix(3)).map(\.id)
        let firstID = try #require(sourceIDs.first)

        model.startPlaybackQueue(
            source: .adHoc,
            trackIDs: sourceIDs,
            startingAt: firstID
        )
        sourceIDs.reverse()

        #expect(
            model.activePlaybackQueue?.orderedTrackIDs
                == Array(model.tracks.prefix(3)).map(\.id)
        )
    }

    @Test("Queue edits register one understandable Undo operation")
    func queueUndo() throws {
        let model = CadenceAppModel()
        let tracks = Array(model.tracks.prefix(4))
        let start = try #require(tracks.first)
        let undoManager = UndoManager()
        model.startPlaybackQueue(
            source: .adHoc,
            trackIDs: tracks.map(\.id),
            startingAt: start.id
        )

        #expect(
            model.removeFromPlaybackQueue(
                [tracks[2].id],
                undoManager: undoManager
            )
        )
        #expect(model.activePlaybackQueue?.upNextTrackIDs == [
            tracks[1].id,
            tracks[3].id,
        ])

        undoManager.undo()

        #expect(model.activePlaybackQueue?.orderedTrackIDs == tracks.map(\.id))
    }

    @Test("Queue edits never mutate canonical album ordering")
    func queueEditIsolation() throws {
        let model = CadenceAppModel()
        let track = try #require(model.tracks.first)
        let originalAlbumOrder = model.selectedAlbumTracks.map(\.id)
        model.play(track)

        model.clearPlaybackQueue()

        #expect(model.selectedAlbumTracks.map(\.id) == originalAlbumOrder)
        #expect(model.activePlaybackQueue?.currentTrackID == track.id)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
