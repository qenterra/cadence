@testable import Cadence
import Foundation
import Testing

struct LibraryTrashPublicationTests {
    @MainActor
    @Test("Bulk Trash refreshes every active resident track source")
    func successfulBulkTrashRefreshesResidentSources() async throws {
        let fixture = try TrashFixture()
        defer { fixture.remove() }
        let store = makeStore(fixture)
        await store.loadInitialLibrary()
        let removedIDs = Set(fixture.trackIDs.prefix(2))
        let remainingIDs = Set(fixture.trackIDs).subtracting(removedIDs)
        let sources = try await prepareResidentSources(
            store: store,
            fixture: fixture
        )

        try await store.moveToTrash(
            trackIDs: Array(removedIDs),
            location: fixture.location
        )

        expectResidentSources(
            store,
            expectedTrackIDs: remainingIDs,
            expectedSearchTrackIDs: sources.searchTrackIDs,
            rule: sources.rule,
            previousSearchVersion: sources.searchVersion
        )
        #expect(store.trashOperations.count == removedIDs.count)
        #expect(
            Set(store.trashOperations.flatMap(\.targetIDs)) == removedIDs
        )
        try await expectVirtualWindow(
            sources.window,
            store: store,
            expectedTrackIDs: remainingIDs,
            previousContentVersion: sources.contentVersion
        )
    }

    @MainActor
    @Test("Partial bulk Trash publishes committed rows before rethrowing")
    func partialBulkTrashRefreshesCommittedResult() async throws {
        let fixture = try TrashFixture()
        defer { fixture.remove() }
        let store = makeStore(fixture)
        await store.loadInitialLibrary()
        let removedID = try #require(fixture.trackIDs.first)
        let missingID = UUID()
        let remainingIDs = Set(fixture.trackIDs).subtracting([removedID])
        let sources = try await prepareResidentSources(
            store: store,
            fixture: fixture
        )
        var observedError: (any Error)?

        do {
            try await store.moveToTrash(
                trackIDs: [removedID, missingID],
                location: fixture.location
            )
            Issue.record("Expected the second Trash target to be missing")
        } catch {
            observedError = error
        }

        let batchError = try requirePartialBatchError(
            observedError,
            failedTargetID: missingID
        )
        expectResidentSources(
            store,
            expectedTrackIDs: remainingIDs,
            expectedSearchTrackIDs: sources.searchTrackIDs,
            rule: sources.rule,
            previousSearchVersion: sources.searchVersion
        )
        let operation = try #require(store.trashOperations.first)
        #expect(store.trashOperations.count == 1)
        #expect(Set(operation.targetIDs) == [removedID])
        #expect(batchError.completedOperationIDs == [operation.id])
        try await expectVirtualWindow(
            sources.window,
            store: store,
            expectedTrackIDs: remainingIDs,
            previousContentVersion: sources.contentVersion
        )
    }

    @MainActor
    @Test("Restore cleanup failure still publishes the committed catalog")
    func restoreCleanupFailureRefreshesCommittedCatalog() async throws {
        let fixture = try TrashFixture()
        defer { fixture.remove() }
        let repository = LibraryRepository(modelContainer: fixture.container)
        let restoredID = try #require(fixture.trackIDs.first)
        let operationID = try await repository.trash(
            targetKind: .track,
            targetID: restoredID,
            location: fixture.location
        )
        let obstacle = try TrashCleanupObstacle(
            operationDirectory: fixture.operationDirectory(operationID)
        )
        defer { obstacle.remove() }
        let store = makeStore(fixture)
        await store.loadInitialLibrary()
        let sources = try await prepareResidentSources(
            store: store,
            fixture: fixture
        )
        var observedError: (any Error)?

        do {
            try await store.restoreTrash(
                operationID: operationID,
                location: fixture.location
            )
            Issue.record("Expected restored Trash cleanup to fail")
        } catch {
            observedError = error
        }

        try requireCleanupError(observedError)
        expectResidentSources(
            store,
            expectedTrackIDs: Set(fixture.trackIDs),
            expectedSearchTrackIDs: sources.searchTrackIDs,
            rule: sources.rule,
            previousSearchVersion: sources.searchVersion
        )
        #expect(store.trashOperations.isEmpty)
        try await expectVirtualWindow(
            sources.window,
            store: store,
            expectedTrackIDs: Set(fixture.trackIDs),
            previousContentVersion: sources.contentVersion
        )
    }

    @MainActor
    @Test("Empty Trash cleanup failure still publishes committed deletion")
    func emptyCleanupFailureRefreshesCommittedTrashList() async throws {
        let fixture = try TrashFixture()
        defer { fixture.remove() }
        let repository = LibraryRepository(modelContainer: fixture.container)
        let targetID = try #require(fixture.trackIDs.first)
        let operationID = try await repository.trash(
            targetKind: .track,
            targetID: targetID,
            location: fixture.location
        )
        let obstacle = try TrashCleanupObstacle(
            operationDirectory: fixture.operationDirectory(operationID)
        )
        defer { obstacle.remove() }
        let store = makeStore(fixture)
        await store.loadInitialLibrary()
        #expect(store.trashOperations.map(\.id) == [operationID])
        var observedError: (any Error)?

        do {
            try await store.emptyTrash(
                operationIDs: [operationID],
                location: fixture.location
            )
            Issue.record("Expected permanent Trash cleanup to fail")
        } catch {
            observedError = error
        }

        try requireCleanupError(observedError)
        #expect(store.trashOperations.isEmpty)
        #expect(Set(store.tracks.map(\.id)) == Set(fixture.trackIDs.dropFirst()))
        #expect(try await repository.trashOperations().isEmpty)
    }
}

private extension LibraryTrashPublicationTests {
    struct ResidentSources {
        let rule: SmartCollectionRuleGroup
        let searchTrackIDs: Set<UUID>
        let searchVersion: TrackTableContentVersion
        let window: LibraryTrackWindow
        let contentVersion: TrackTableContentVersion
    }

    @MainActor
    func makeStore(_ fixture: TrashFixture) -> LibraryStore {
        LibraryStore(
            container: fixture.container,
            package: ManagedLibraryPackage(location: fixture.location)
        )
    }

    @MainActor
    func prepareResidentSources(
        store: LibraryStore,
        fixture: TrashFixture
    ) async throws -> ResidentSources {
        await store.loadPlaylists()
        await store.browseTracks(albumID: fixture.albumID)
        let searchTrackID = try #require(fixture.trackIDs.last)
        await store.searchCatalog(searchTrackID.uuidString)
        let rule = trashArtistRule()
        await store.loadSmartCollectionSummaries(rules: [rule])
        await store.loadSmartCollectionResult(rule: rule)
        let window = try #require(store.allTracksWindow)
        await window.configure(
            totalCount: store.catalogCounts.liveTrackCount,
            query: store.trackQuery,
            contentVersion: store.allTracksWindowContentVersion
        )
        let expectedIDs = Set(store.tracks.map(\.id))
        expectResidentSources(
            store,
            expectedTrackIDs: expectedIDs,
            expectedSearchTrackIDs: [searchTrackID],
            rule: rule
        )
        return ResidentSources(
            rule: rule,
            searchTrackIDs: [searchTrackID],
            searchVersion: store.catalogSearchTracksVersion,
            window: window,
            contentVersion: store.allTracksWindowContentVersion
        )
    }

    @MainActor
    func expectResidentSources(
        _ store: LibraryStore,
        expectedTrackIDs: Set<UUID>,
        expectedSearchTrackIDs: Set<UUID>,
        rule: SmartCollectionRuleGroup,
        previousSearchVersion: TrackTableContentVersion? = nil
    ) {
        #expect(Set(store.tracks.map(\.id)) == expectedTrackIDs)
        #expect(Set(store.browserTracks.map(\.id)) == expectedTrackIDs)
        #expect(
            Set(store.selectedPlaylistTracks.map(\.id)) == expectedTrackIDs
        )
        #expect(
            Set(store.catalogSearchResults.tracks.map(\.id))
                == expectedSearchTrackIDs
        )
        if let previousSearchVersion {
            #expect(store.catalogSearchTracksVersion != previousSearchVersion)
        }
        #expect(
            Set(store.smartCollectionTracks(for: rule).map(\.id))
                == expectedTrackIDs
        )
        #expect(
            store.smartCollectionSummary(for: rule).count
                == expectedTrackIDs.count
        )
    }

    @MainActor
    func expectVirtualWindow(
        _ window: LibraryTrackWindow,
        store: LibraryStore,
        expectedTrackIDs: Set<UUID>,
        previousContentVersion: TrackTableContentVersion
    ) async throws {
        #expect(store.allTracksWindowContentVersion != previousContentVersion)
        await window.configure(
            totalCount: store.catalogCounts.liveTrackCount,
            query: store.trackQuery,
            contentVersion: store.allTracksWindowContentVersion
        )
        let windowIDs = Set(
            (0 ..< store.catalogCounts.liveTrackCount).compactMap {
                window.track(at: $0)?.id
            }
        )
        #expect(windowIDs == expectedTrackIDs)
    }

    func trashArtistRule() -> SmartCollectionRuleGroup {
        SmartCollectionRuleGroup(
            combinator: .all,
            children: [
                .condition(
                    SmartCollectionRuleCondition(
                        field: .artist,
                        operator: .contains,
                        value: .text("Trash Artist")
                    )
                ),
            ]
        )
    }

    func requireCleanupError(_ observedError: (any Error)?) throws {
        let error = try #require(
            observedError as? LibraryTrashTransactionError
        )
        #expect(error.phase == .cleanup)
        #expect(error.recoveryDirectory.isPresent)
    }

    func requirePartialBatchError(
        _ observedError: (any Error)?,
        failedTargetID: UUID
    ) throws -> LibraryTrashBatchError {
        let error = try #require(observedError)
        let batchError = try #require(error as? LibraryTrashBatchError)
        #expect(batchError.completedTargetCount == 1)
        #expect(batchError.requestedTargetCount == 2)
        #expect(batchError.failedTargetID == failedTargetID)
        let cause = try #require(batchError.cause as? LibraryTrashError)
        switch cause {
        case .missingTarget:
            break
        default:
            Issue.record("Expected the original missing-target cause")
        }
        #expect(
            error.localizedDescription.contains(
                "1 of 2 selected tracks moved to Trash"
            )
        )
        return batchError
    }
}

private struct TrashCleanupObstacle {
    let directory: URL

    init(operationDirectory: URL) throws {
        directory = operationDirectory.appending(
            path: "Cleanup-Obstacle",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("retain".utf8).write(
            to: directory.appending(path: "retained.txt")
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: directory.path
        )
    }

    func remove() {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: directory.path
        )
    }
}
