@testable import Cadence
import Foundation
import Testing

@MainActor
func captureRecoveryTestError(
    _ operation: () async throws -> Void
) async -> (any Error)? {
    do {
        try await operation()
        Issue.record("Expected the operation to fail")
        return nil
    } catch {
        return error
    }
}

@MainActor
func configureRecoveryWindow(
    _ window: LibraryTrackWindow,
    store: LibraryStore
) async {
    await window.configure(
        totalCount: store.catalogCounts.liveTrackCount,
        query: store.trackQuery,
        contentVersion: store.allTracksWindowContentVersion
    )
}

func recoveryTestUUID(_ source: String) throws -> UUID {
    try #require(UUID(uuidString: source))
}

@MainActor
struct LyricsRecoveryStoreContext {
    let fixture: ManagedLyricsFixture
    let store: LibraryStore
    let window: LibraryTrackWindow
    let recoveredIndex: Int
    let failedIndex: Int
    let initialRevision: Int
    let recoveredText: String
    let failedTrackID: UUID

    var expectedError: ManagedLyricsServiceError {
        .invalidDocument("Time exceeds the track duration.")
    }

    var invalidDocument: LyricDocument {
        LyricDocument(
            trackID: failedTrackID,
            lines: [LyricLine(text: "Invalid B", startTime: 181)]
        )
    }

    static func make() async throws -> Self {
        let fixture = try ManagedLyricsFixture(trackCount: 2)
        let failedTrackID = try #require(fixture.additionalTrackIDs.first)
        let operationID = try recoveryTestUUID(
            "30000000-0000-0000-0000-000000000001"
        )
        let recoveredText = "RecoveryNeedleAlpha"
        let store = LibraryStore()
        try await store.attach(
            repository: fixture.repository,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await configureRecoveryWindow(window, store: store)
        let recoveredIndex = try #require(
            window.index(ofTrackID: fixture.trackID)
        )
        let failedIndex = try #require(window.index(ofTrackID: failedTrackID))
        let initialRevision = window.revision
        try installLyricRecovery(
            fixture,
            operationID: operationID,
            text: recoveredText
        )
        return Self(
            fixture: fixture,
            store: store,
            window: window,
            recoveredIndex: recoveredIndex,
            failedIndex: failedIndex,
            initialRevision: initialRevision,
            recoveredText: recoveredText,
            failedTrackID: failedTrackID
        )
    }

    func recoveredMatches() async -> [LyricsCatalogSearchResult] {
        await store.lyricsCatalogResults(query: recoveredText, limit: 10)
    }

    func remove() async throws {
        try await store.detach()
        fixture.remove()
    }

    private static func installLyricRecovery(
        _ fixture: ManagedLyricsFixture,
        operationID: UUID,
        text: String
    ) throws {
        let data = Data("[00:01.000]\(text)\n".utf8)
        try data.write(to: fixture.package.lyricURL(trackID: fixture.trackID))
        try ManagedLyricEditManifestStore(package: fixture.package).save(
            ManagedLyricEditManifest(
                operationID: operationID,
                trackID: fixture.trackID,
                targetRelativePath: "Lyrics/\(fixture.trackID.uuidString).lrc",
                previousContentHash: nil,
                newContentHash: ContentHasher().sha256(of: data),
                newTimingStatus: .synchronized,
                state: .fileInstalled
            )
        )
    }
}

@MainActor
struct ArtworkRecoveryStoreContext {
    let fixture: ManagedArtworkFixture
    let store: LibraryStore
    let window: LibraryTrackWindow
    let initialWindowRevision: Int
    let initialContentVersion: TrackTableContentVersion
    let artworkID: UUID
    let recoveredAsset: ArtworkAsset
    let sentinelAsset: ArtworkAsset

    var invalidRequest: ManagedArtworkEditRequest {
        ManagedArtworkEditRequest(
            ownerKind: .artist,
            ownerID: fixture.artistID,
            data: Data("Invalid B".utf8),
            scale: 1,
            normalizedOffset: .zero
        )
    }

    static func make() async throws -> Self {
        let fixture = try ManagedArtworkFixture()
        let operationID = try recoveryTestUUID(
            "40000000-0000-0000-0000-000000000001"
        )
        let artworkID = try recoveryTestUUID(
            "40000000-0000-0000-0000-000000000002"
        )
        let sentinelID = try recoveryTestUUID(
            "40000000-0000-0000-0000-000000000003"
        )
        let manifest = try fixture.manifest(
            state: .fileInstalled,
            operationID: operationID,
            artworkID: artworkID
        )
        let recoveredArtwork = try #require(manifest.newArtwork)
        let recoveredAsset = ArtworkAsset(
            id: recoveredArtwork.id,
            revision: recoveredArtwork.revision,
            data: fixture.image
        )
        let sentinelAsset = ArtworkAsset(
            id: sentinelID,
            revision: 7,
            data: Data("Unrelated cache sentinel".utf8)
        )
        let store = LibraryStore()
        try await store.attach(
            repository: fixture.repository,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await configureRecoveryWindow(window, store: store)
        let initialWindowRevision = window.revision
        let initialContentVersion = store.allTracksWindowContentVersion
        store.artworkAssetCache.insert(recoveredAsset)
        store.artworkAssetCache.insert(sentinelAsset)
        try fixture.installNewFile(for: manifest)
        try fixture.store.save(manifest)
        return Self(
            fixture: fixture,
            store: store,
            window: window,
            initialWindowRevision: initialWindowRevision,
            initialContentVersion: initialContentVersion,
            artworkID: artworkID,
            recoveredAsset: recoveredAsset,
            sentinelAsset: sentinelAsset
        )
    }

    func configureWindow() async {
        await configureRecoveryWindow(window, store: store)
    }

    func recoveredCachedAsset() -> ArtworkAsset? {
        store.artworkAssetCache.asset(
            id: recoveredAsset.id,
            revision: recoveredAsset.revision
        )
    }

    func sentinelCachedAsset() -> ArtworkAsset? {
        store.artworkAssetCache.asset(
            id: sentinelAsset.id,
            revision: sentinelAsset.revision
        )
    }

    func remove() async throws {
        try await store.detach()
        fixture.remove()
    }
}
