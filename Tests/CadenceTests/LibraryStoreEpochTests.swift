@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibraryStoreEpochTests {
    @Test("Library identity advances on every attach and detach")
    func libraryIdentityAdvancesMonotonically() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let store = LibraryStore()
        let initialEpoch = store.libraryEpoch

        try await store.attach(repository: libraryA.repository)
        let firstAttachEpoch = store.libraryEpoch
        #expect(firstAttachEpoch > initialEpoch)

        try await store.attach(repository: libraryA.repository)
        let repeatedAttachEpoch = store.libraryEpoch
        #expect(repeatedAttachEpoch > firstAttachEpoch)

        let libraryAContext = store.captureLibraryContext()
        #expect(store.isCurrentLibraryContext(libraryAContext))
        try await store.attach(repository: libraryB.repository)
        let libraryBAttachEpoch = store.libraryEpoch
        #expect(libraryBAttachEpoch > repeatedAttachEpoch)
        #expect(!store.isCurrentLibraryContext(libraryAContext))
        #expect(
            !store.isCurrentLibraryContext(
                LibraryStoreContext(
                    epoch: libraryBAttachEpoch,
                    repository: libraryA.repository
                )
            )
        )

        try await store.detach()
        #expect(store.libraryEpoch > libraryBAttachEpoch)
    }

    @Test("A stale initial snapshot cannot replace an attached library")
    func staleInitialSnapshotIsDiscarded() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let snapshotA = try await makeInitialEpochSnapshot(
            from: libraryA.repository
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        #expect(store.tracks.map(\.title) == ["Library B"])
        try await store.attach(repository: libraryA.repository)

        let gate = LibraryEpochResultGate(snapshotA)
        let staleLoad = Task { @MainActor in
            await store.loadInitialLibrary { _ in
                await gate.suspend()
            }
        }
        await gate.waitUntilSuspended()
        #expect(store.availability == .loading)

        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        #expect(store.tracks.map(\.title) == ["Library B"])

        await gate.resume()
        await staleLoad.value

        #expect(store.repository === libraryB.repository)
        #expect(store.tracks.map(\.title) == ["Library B"])
        #expect(store.availability == .ready)
        #expect(store.operationFailure == nil)
    }

    @Test("A stale recent-play result cannot publish into an attached library")
    func staleRecentlyPlayedResultIsDiscarded() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryBDate = Date(timeIntervalSince1970: 200)
        let libraryB = try LibraryEpochFixture(
            title: "Library B",
            lastPlayedAt: libraryBDate
        )
        let libraryAPlaybackDate = Date(timeIntervalSince1970: 100)
        let libraryAProjection = try await libraryA.repository
            .recordRecentlyPlayed(
                trackID: libraryA.trackID,
                at: libraryAPlaybackDate
            )
        let libraryARecentTracks = try await libraryA.repository
            .recentlyPlayedTracks()
        let libraryAResult = LibraryRecentPlaybackResult(
            projection: libraryAProjection,
            recentlyPlayedTracks: libraryARecentTracks
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        #expect(store.recentlyPlayedTracks.map(\.title) == ["Library B"])
        try await store.attach(repository: libraryA.repository)

        let gate = LibraryEpochResultGate(libraryAResult)
        let stalePlayback = Task { @MainActor in
            await store.recordRecentlyPlayed(
                trackID: libraryA.trackID,
                at: libraryAPlaybackDate,
                operation: { _, _, _ in
                    await gate.suspend()
                }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        #expect(store.recentlyPlayedTracks.map(\.title) == ["Library B"])

        await gate.resume()
        #expect(await stalePlayback.value)

        #expect(store.repository === libraryB.repository)
        #expect(store.tracks.map(\.title) == ["Library B"])
        #expect(store.recentlyPlayedTracks.map(\.title) == ["Library B"])
        #expect(store.recentlyPlayedTracks.first?.lastPlayedAt == libraryBDate)
        #expect(store.operationFailure == nil)
    }

    @Test("A durable recent-play write survives a cache reload failure")
    func durableRecentPlaySurvivesReloadFailure() async throws {
        let library = try LibraryEpochFixture(title: "Library")
        let playbackDate = Date(timeIntervalSince1970: 300)
        let store = LibraryStore()
        try await store.attach(repository: library.repository)
        await store.loadInitialLibrary()

        let succeeded = await store.recordRecentlyPlayed(
            trackID: library.trackID,
            at: playbackDate,
            recentTracksLoader: { _ in
                throw LibraryEpochTestError.cacheReload
            }
        )

        #expect(succeeded)
        #expect(store.tracks.first?.lastPlayedAt == playbackDate)
        #expect(store.operationFailure?.operation == .recentPlayback)
        let durableRecentTracks = try await library.repository
            .recentlyPlayedTracks()
        #expect(durableRecentTracks.first?.lastPlayedAt == playbackDate)
    }

    @Test("An older snapshot cannot replace a newer load in the same library")
    func olderSameLibrarySnapshotIsDiscarded() async throws {
        let library = try LibraryEpochFixture(title: "Attached Library")
        let oldLibrary = try LibraryEpochFixture(title: "Old Snapshot")
        let newLibrary = try LibraryEpochFixture(title: "New Snapshot")
        let oldSnapshot = try await makeInitialEpochSnapshot(
            from: oldLibrary.repository
        )
        let newSnapshot = try await makeInitialEpochSnapshot(
            from: newLibrary.repository
        )
        let store = LibraryStore()
        try await store.attach(repository: library.repository)
        let oldGate = LibraryEpochResultGate(oldSnapshot)

        let oldLoad = Task { @MainActor in
            await store.loadInitialLibrary { _ in
                await oldGate.suspend()
            }
        }
        await oldGate.waitUntilSuspended()

        await store.loadInitialLibrary { _ in newSnapshot }
        #expect(store.tracks.map(\.title) == ["New Snapshot"])

        await oldGate.resume()
        await oldLoad.value

        #expect(store.tracks.map(\.title) == ["New Snapshot"])
        #expect(store.availability == .ready)
    }

    @Test("An older snapshot error cannot fail a newer load in the same library")
    func olderSameLibrarySnapshotErrorIsDiscarded() async throws {
        let library = try LibraryEpochFixture(title: "Attached Library")
        let newLibrary = try LibraryEpochFixture(title: "New Snapshot")
        let newSnapshot = try await makeInitialEpochSnapshot(
            from: newLibrary.repository
        )
        let staleResult = Result<
            InitialLibrarySnapshot,
            LibraryEpochTestError
        >.failure(.staleOperation)
        let oldGate = LibraryEpochResultGate(staleResult)
        let store = LibraryStore()
        try await store.attach(repository: library.repository)

        let oldLoad = Task { @MainActor in
            await store.loadInitialLibrary { _ in
                try await oldGate.suspend().get()
            }
        }
        await oldGate.waitUntilSuspended()

        await store.loadInitialLibrary { _ in newSnapshot }
        #expect(store.tracks.map(\.title) == ["New Snapshot"])

        await oldGate.resume()
        await oldLoad.value

        #expect(store.tracks.map(\.title) == ["New Snapshot"])
        #expect(store.availability == .ready)
    }
}
