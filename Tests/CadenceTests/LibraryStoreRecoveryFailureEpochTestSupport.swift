@testable import Cadence
import Foundation
import Testing

@MainActor
struct StaleLyricsStoreContext {
    let libraryB: LibraryEpochFixture
    let store: LibraryStore
    let gate: LibraryEpochResultGate<
        Result<ManagedLyricsSaveResult, ManagedLyricsSaveFailure>
    >
    let task: Task<Void, Error>
    let window: LibraryTrackWindow
    let initialWindowRevision: Int
    let initialContentVersion: TrackTableContentVersion

    static func make() async throws -> Self {
        let trackID = try recoveryTestUUID(
            "50000000-0000-0000-0000-000000000001"
        )
        let operationID = try recoveryTestUUID(
            "50000000-0000-0000-0000-000000000002"
        )
        let libraryA = try LibraryEpochFixture(
            title: "Library A",
            trackID: trackID
        )
        let libraryB = try LibraryEpochFixture(
            title: "Library B",
            trackID: trackID
        )
        try await commitRecoveredLyrics(in: libraryA, trackID: trackID)
        let gate = LibraryEpochResultGate(
            Result<ManagedLyricsSaveResult, ManagedLyricsSaveFailure>.failure(
                makeFailure(trackID: trackID, operationID: operationID)
            )
        )
        let packageA = makeEpochDummyPackage(label: "Lyrics-Recovery-A")
        let packageB = makeEpochDummyPackage(label: "Lyrics-Recovery-B")
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository, package: packageA)
        let task = startTask(
            store: store,
            trackID: trackID,
            gate: gate
        )
        await gate.waitUntilSuspended()
        try await store.attach(repository: libraryB.repository, package: packageB)
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await configureRecoveryWindow(window, store: store)
        return Self(
            libraryB: libraryB,
            store: store,
            gate: gate,
            task: task,
            window: window,
            initialWindowRevision: window.revision,
            initialContentVersion: store.allTracksWindowContentVersion
        )
    }

    private static func startTask(
        store: LibraryStore,
        trackID: UUID,
        gate: LibraryEpochResultGate<
            Result<ManagedLyricsSaveResult, ManagedLyricsSaveFailure>
        >
    ) -> Task<Void, Error> {
        Task { @MainActor in
            try await store.saveLyrics(
                LyricDocument(
                    trackID: trackID,
                    lines: [LyricLine(text: "Stale B", startTime: 1)]
                ),
                operation: { _, _ in try await gate.suspend().get() }
            )
        }
    }

    private static func commitRecoveredLyrics(
        in library: LibraryEpochFixture,
        trackID: UUID
    ) async throws {
        try await library.repository.applyLyricMutation(
            trackID: trackID,
            mutation: .upsert(
                relativePath: "Lyrics/\(trackID.uuidString).lrc",
                contentHash: String(repeating: "a", count: 64),
                timingStatus: .synchronized,
                modifiedAt: Date(timeIntervalSince1970: 500)
            )
        )
    }

    private static func makeFailure(
        trackID: UUID,
        operationID: UUID
    ) -> ManagedLyricsSaveFailure {
        ManagedLyricsSaveFailure(
            recovery: ManagedLyricsRecoveryResult(
                recoveredOperationIDs: [operationID],
                rolledBackOperationIDs: [],
                affectedTrackIDs: [trackID]
            ),
            underlyingError: ManagedLyricsServiceError.invalidDocument(
                "Stale current save"
            )
        )
    }
}

@MainActor
struct StaleArtworkStoreContext {
    let libraryB: LibraryEpochFixture
    let store: LibraryStore
    let gate: LibraryEpochResultGate<
        Result<ManagedArtworkMutationResult, ManagedArtworkMutationFailure>
    >
    let task: Task<ManagedArtworkMutationResult, Error>
    let window: LibraryTrackWindow
    let initialWindowRevision: Int
    let initialContentVersion: TrackTableContentVersion
    let sentinelAsset: ArtworkAsset

    static func make() async throws -> Self {
        let ids = try StaleArtworkRecoveryIDs.make()
        let libraryA = try LibraryEpochFixture(
            title: "Library A",
            trackID: ids.trackID
        )
        let libraryB = try LibraryEpochFixture(
            title: "Library B",
            trackID: ids.trackID
        )
        let gate = makeGate(ids: ids)
        let packageA = makeEpochDummyPackage(label: "Artwork-Recovery-A")
        let packageB = makeEpochDummyPackage(label: "Artwork-Recovery-B")
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository, package: packageA)
        let task = startTask(
            store: store,
            package: packageA,
            trackID: ids.trackID,
            gate: gate
        )
        await gate.waitUntilSuspended()
        try await store.attach(repository: libraryB.repository, package: packageB)
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await configureRecoveryWindow(window, store: store)
        let sentinelAsset = ArtworkAsset(
            id: ids.artworkID,
            revision: 9,
            data: Data("Current library sentinel".utf8)
        )
        store.artworkAssetCache.insert(sentinelAsset)
        return Self(
            libraryB: libraryB,
            store: store,
            gate: gate,
            task: task,
            window: window,
            initialWindowRevision: window.revision,
            initialContentVersion: store.allTracksWindowContentVersion,
            sentinelAsset: sentinelAsset
        )
    }

    func cachedSentinel() -> ArtworkAsset? {
        store.artworkAssetCache.asset(
            id: sentinelAsset.id,
            revision: sentinelAsset.revision
        )
    }

    private static func makeGate(
        ids: StaleArtworkRecoveryIDs
    ) -> LibraryEpochResultGate<
        Result<ManagedArtworkMutationResult, ManagedArtworkMutationFailure>
    > {
        LibraryEpochResultGate(
            Result<
                ManagedArtworkMutationResult,
                ManagedArtworkMutationFailure
            >.failure(makeFailure(ids: ids))
        )
    }

    private static func startTask(
        store: LibraryStore,
        package: ManagedLibraryPackage,
        trackID: UUID,
        gate: LibraryEpochResultGate<
            Result<ManagedArtworkMutationResult, ManagedArtworkMutationFailure>
        >
    ) -> Task<ManagedArtworkMutationResult, Error> {
        Task { @MainActor in
            try await store.setArtwork(
                ManagedArtworkEditRequest(
                    ownerKind: .track,
                    ownerID: trackID,
                    data: Data([0]),
                    scale: 1,
                    normalizedOffset: .zero
                ),
                location: package.location,
                operation: { _, _ in try await gate.suspend().get() }
            )
        }
    }

    private static func makeFailure(
        ids: StaleArtworkRecoveryIDs
    ) -> ManagedArtworkMutationFailure {
        ManagedArtworkMutationFailure(
            recovery: ManagedArtworkRecoveryResult(
                recoveredOperationIDs: [ids.operationID],
                rolledBackOperationIDs: [],
                effects: [
                    ManagedArtworkPublicationEffect(
                        ownerKind: .track,
                        ownerID: ids.trackID,
                        previousArtworkID: nil,
                        newArtworkID: ids.artworkID
                    ),
                ]
            ),
            underlyingError: ManagedArtworkEditError.invalidImage
        )
    }
}

private struct StaleArtworkRecoveryIDs {
    let trackID: UUID
    let operationID: UUID
    let artworkID: UUID

    static func make() throws -> Self {
        try Self(
            trackID: recoveryTestUUID(
                "60000000-0000-0000-0000-000000000001"
            ),
            operationID: recoveryTestUUID(
                "60000000-0000-0000-0000-000000000002"
            ),
            artworkID: recoveryTestUUID(
                "60000000-0000-0000-0000-000000000003"
            )
        )
    }
}
