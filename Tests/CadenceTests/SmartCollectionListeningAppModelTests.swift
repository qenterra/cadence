@testable import Cadence
import Foundation
import Testing

@MainActor
struct SmartCollectionListeningAppModelTests {
    @Test("Saved projections remain independent from editor live results")
    func savedAndDraftIsolation() throws {
        let collection = allTracksCollection(id: testID(1))
        let model = CadenceAppModel.preview(smartCollections: [collection])
        let savedIDs = model.selectedSmartCollectionCanonicalTracks.map(\.id)

        model.requestEditSelectedSmartCollection()
        let rootID = try #require(model.smartCollectionDraft?.rule.id)
        model.addSmartCollectionCondition(
            SmartCollectionRuleCondition(
                field: .artist,
                operator: .is,
                value: .text("North Assembly")
            ),
            to: rootID
        )

        #expect(model.smartCollectionLiveTracks.count < savedIDs.count)
        #expect(model.selectedSmartCollectionCanonicalTracks.map(\.id) == savedIDs)
    }

    @Test("Sort descriptors and visible ordering are independent by collection")
    func independentSorting() {
        let first = allTracksCollection(id: testID(10), name: "First")
        let second = allTracksCollection(id: testID(11), name: "Second")
        let model = CadenceAppModel.preview(smartCollections: [first, second])

        model.activateSelectedSmartCollectionSort(.title)
        let firstOrder = model.selectedSmartCollectionVisibleTracks.map(\.id)
        #expect(model.selectedSmartCollectionSortDescriptor.field == .title)

        model.requestSelectSmartCollection(second.id)
        #expect(model.selectedSmartCollectionSortDescriptor == .canonical)
        #expect(
            model.selectedSmartCollectionVisibleTracks.map(\.id)
                == model.tracks.map(\.id)
        )

        model.requestSelectSmartCollection(first.id)
        #expect(model.selectedSmartCollectionVisibleTracks.map(\.id) == firstOrder)
    }

    @Test("List metadata uses saved matches and transient draft live results")
    func listMetadata() throws {
        let collection = allTracksCollection(id: testID(20))
        let model = CadenceAppModel.preview(smartCollections: [collection])
        let savedItem = try #require(model.smartCollectionListItems.first)

        #expect(savedItem.matchCount == model.tracks.count)
        #expect(
            savedItem.totalDuration
                == model.tracks.reduce(0) { $0 + $1.duration }
        )

        model.requestNewSmartCollection(
            draftID: testID(21),
            rootID: testID(22)
        )
        let transient = try #require(model.smartCollectionListItems.last)

        #expect(transient.isTransient)
        #expect(transient.matchCount == model.tracks.count)
        #expect(transient.totalDuration == savedItem.totalDuration)
    }

    @Test("Play uses visible order and keeps a stable queue snapshot")
    func playAndSnapshot() throws {
        let collection = allTracksCollection(id: testID(30))
        let model = CadenceAppModel.preview(smartCollections: [collection])
        model.activateSelectedSmartCollectionSort(.title)
        let visibleIDs = model.selectedSmartCollectionVisibleTracks.map(\.id)
        let start = try #require(
            model.selectedSmartCollectionVisibleTracks.dropFirst().first
        )
        model.selectTrack(start)

        let played = model.playSelectedSmartCollection()
        #expect(played)
        #expect(model.activePlaybackQueue?.source == .smartCollection(collection.id))
        #expect(model.activePlaybackQueue?.orderedTrackIDs == visibleIDs)
        #expect(model.currentTrackID == start.id)

        model.activateSelectedSmartCollectionSort(.title)
        #expect(model.activePlaybackQueue?.orderedTrackIDs == visibleIDs)
    }

    @Test("Row activation and seeded Shuffle create collection queues")
    func rowAndShuffle() throws {
        let collection = allTracksCollection(id: testID(40))
        let model = CadenceAppModel.preview(smartCollections: [collection])
        let row = try #require(model.selectedSmartCollectionVisibleTracks.last)

        #expect(model.playSelectedSmartCollectionTrack(row))
        #expect(model.currentTrackID == row.id)

        var generator = ListeningSeededGenerator(seed: 72)
        #expect(model.shuffleSelectedSmartCollection(using: &generator))
        let queue = try #require(model.activePlaybackQueue)

        #expect(queue.source == .smartCollection(collection.id))
        #expect(queue.isShuffled)
        #expect(Set(queue.orderedTrackIDs) == Set(model.tracks.map(\.id)))
        #expect(queue.orderedTrackIDs.count == model.tracks.count)
    }
}

private extension SmartCollectionListeningAppModelTests {
    func allTracksCollection(
        id: UUID,
        name: String = "All Tracks"
    ) -> SmartCollectionPreview {
        SmartCollectionPreview(
            id: id,
            name: name,
            rule: SmartCollectionRuleGroup(
                id: testID(UInt32(id.uuid.15) + 100),
                combinator: .all,
                children: []
            ),
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testID(_ value: UInt32) -> UUID {
        UUID(
            uuidString: String(
                format: "CA300000-0000-0000-0000-%012X",
                value
            )
        ) ?? UUID()
    }
}

private struct ListeningSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 2_862_933_555_777_941_757 &+ 3_037_000_493
        return state
    }
}
