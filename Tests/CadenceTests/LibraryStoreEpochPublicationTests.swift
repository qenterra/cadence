@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibraryStoreEpochPublicationTests {
    @Test("A stale favorite success cannot insert an old-library row")
    func staleFavoritePublicationIsDiscarded() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let staleProjection = try await libraryA.repository.setTrackFavorite(
            id: libraryA.trackID,
            isFavorite: true
        )
        let gate = LibraryEpochResultGate(staleProjection)
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository)

        let staleFavorite = Task { @MainActor in
            try await store.setTrackFavorite(
                id: libraryA.trackID,
                isFavorite: true,
                operation: { _, _, _ in await gate.suspend() }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        let currentVersion = store.favoriteTracksVersion

        await gate.resume()
        let result = try await staleFavorite.value

        #expect(result == staleProjection)
        #expect(store.repository === libraryB.repository)
        #expect(store.favoriteTracks.isEmpty)
        #expect(store.favoriteTrackIDs.isEmpty)
        #expect(store.favoriteTracksVersion == currentVersion)
    }

    @Test("A stale lyric save cannot refresh the attached library")
    func staleLyricsPublicationIsDiscarded() async throws {
        let sharedTrackID = UUID()
        let libraryA = try LibraryEpochFixture(
            title: "Library A",
            trackID: sharedTrackID
        )
        let libraryB = try LibraryEpochFixture(
            title: "Library B",
            trackID: sharedTrackID
        )
        let packageA = makeEpochDummyPackage(label: "Lyrics-A")
        let packageB = makeEpochDummyPackage(label: "Lyrics-B")
        let result = ManagedLyricsSaveResult(
            recovery: .empty,
            savedTrackID: sharedTrackID
        )
        let gate = LibraryEpochResultGate(result)
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository, package: packageA)

        let staleSave = Task { @MainActor in
            try await store.saveLyrics(
                LyricDocument(
                    trackID: sharedTrackID,
                    lines: [LyricLine(text: "Stale", startTime: 1)]
                ),
                operation: { _, _ in await gate.suspend() }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository, package: packageB)
        await store.loadInitialLibrary()
        #expect(store.tracks.first?.hasSynchronizedLyrics == false)
        try await libraryB.repository.applyLyricMutation(
            trackID: sharedTrackID,
            mutation: .upsert(
                relativePath: "Lyrics/current.lrc",
                contentHash: String(repeating: "b", count: 64),
                timingStatus: .synchronized,
                modifiedAt: Date(timeIntervalSince1970: 500)
            )
        )

        await gate.resume()
        try await staleSave.value

        #expect(store.repository === libraryB.repository)
        #expect(store.tracks.first?.title == "Library B")
        #expect(store.tracks.first?.hasSynchronizedLyrics == false)
    }

    @Test("A stale artwork success returns no effects for the attached library")
    func staleArtworkPublicationIsDiscarded() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let packageA = makeEpochDummyPackage(label: "Artwork-A")
        let packageB = makeEpochDummyPackage(label: "Artwork-B")
        let artworkID = UUID()
        let staleResult = ManagedArtworkMutationResult(
            primaryArtworkID: artworkID,
            effects: [
                ManagedArtworkPublicationEffect(
                    ownerKind: .track,
                    ownerID: libraryA.trackID,
                    previousArtworkID: nil,
                    newArtworkID: artworkID
                ),
            ]
        )
        let gate = LibraryEpochResultGate(staleResult)
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository, package: packageA)

        let staleArtwork = Task { @MainActor in
            try await store.setArtwork(
                ManagedArtworkEditRequest(
                    ownerKind: .track,
                    ownerID: libraryA.trackID,
                    data: Data([0]),
                    scale: 1,
                    normalizedOffset: .zero
                ),
                location: packageA.location,
                operation: { _, _ in await gate.suspend() }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository, package: packageB)
        await store.loadInitialLibrary()
        let currentVersion = store.allTracksWindowContentVersion

        await gate.resume()
        let result = try await staleArtwork.value

        #expect(result.primaryArtworkID == artworkID)
        #expect(result.effects.isEmpty)
        #expect(store.repository === libraryB.repository)
        #expect(store.allTracksWindowContentVersion == currentVersion)
    }

    @Test("An artwork payload finishing after reattachment cannot publish")
    func staleArtworkPayloadIsDiscarded() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let packageA = makeEpochDummyPackage(label: "Artwork-Payload-A")
        let packageB = makeEpochDummyPackage(label: "Artwork-Payload-B")
        let artworkID = UUID()
        let effect = ManagedArtworkPublicationEffect(
            ownerKind: .track,
            ownerID: libraryA.trackID,
            previousArtworkID: nil,
            newArtworkID: artworkID
        )
        let result = ManagedArtworkMutationResult(
            primaryArtworkID: artworkID,
            effects: [effect]
        )
        let staleTrack = try #require(
            try await libraryA.repository.track(id: libraryA.trackID)
        )
        let gate = LibraryEpochResultGate(
            LibraryArtworkPublicationPayload(
                tracksByID: [libraryA.trackID: staleTrack],
                albumsByID: [:],
                artistsByID: [:],
                playlistsByID: [:]
            )
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository, package: packageA)

        let staleArtwork = Task { @MainActor in
            try await store.setArtwork(
                ManagedArtworkEditRequest(
                    ownerKind: .track,
                    ownerID: libraryA.trackID,
                    data: Data([0]),
                    scale: 1,
                    normalizedOffset: .zero
                ),
                location: packageA.location,
                operation: { _, _ in result },
                publicationLoader: { _, _ in await gate.suspend() }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository, package: packageB)
        await store.loadInitialLibrary()
        let currentEpoch = store.libraryEpoch

        await gate.resume()
        let staleResult = try await staleArtwork.value

        #expect(staleResult.effects.isEmpty)
        #expect(store.libraryEpoch == currentEpoch)
        #expect(store.repository === libraryB.repository)
        #expect(store.tracks.map(\.title) == ["Library B"])
        #expect(store.artworkPublication == nil)
    }

    @Test("A superseded artwork payload cannot replace the latest generation")
    func supersededArtworkPayloadIsDiscarded() async throws {
        let library = try LibraryEpochFixture(title: "Current Library")
        let package = makeEpochDummyPackage(label: "Artwork-Generation")
        let store = LibraryStore()
        try await store.attach(repository: library.repository, package: package)
        await store.loadInitialLibrary()
        let original = try #require(store.tracks.first)
        let staleArtworkID = UUID()
        let currentArtworkID = UUID()
        let staleEffect = ManagedArtworkPublicationEffect(
            ownerKind: .track,
            ownerID: original.id,
            previousArtworkID: nil,
            newArtworkID: staleArtworkID
        )
        let currentEffect = ManagedArtworkPublicationEffect(
            ownerKind: .track,
            ownerID: original.id,
            previousArtworkID: staleArtworkID,
            newArtworkID: currentArtworkID
        )
        let stalePayload = artworkPayload(
            track: original,
            artworkID: staleArtworkID
        )
        let currentPayload = artworkPayload(
            track: original,
            artworkID: currentArtworkID
        )
        let gate = LibraryEpochResultGate(stalePayload)
        let request = ManagedArtworkEditRequest(
            ownerKind: .track,
            ownerID: original.id,
            data: Data([0]),
            scale: 1,
            normalizedOffset: .zero
        )

        let staleArtwork = Task { @MainActor in
            try await store.setArtwork(
                request,
                location: package.location,
                operation: { _, _ in
                    ManagedArtworkMutationResult(
                        primaryArtworkID: staleArtworkID,
                        effects: [staleEffect]
                    )
                },
                publicationLoader: { _, _ in await gate.suspend() }
            )
        }
        await gate.waitUntilSuspended()

        _ = try await store.setArtwork(
            request,
            location: package.location,
            operation: { _, _ in
                ManagedArtworkMutationResult(
                    primaryArtworkID: currentArtworkID,
                    effects: [currentEffect]
                )
            },
            publicationLoader: { _, _ in currentPayload }
        )
        let latestGeneration = store.artworkPublication?.generation
        await gate.resume()
        _ = try await staleArtwork.value

        #expect(store.tracks.first?.artworkID == currentArtworkID)
        #expect(store.artworkPublication?.effects == [currentEffect])
        #expect(store.artworkPublication?.generation == latestGeneration)
    }

    @Test("A stale Trash success cannot refresh the attached library")
    func staleTrashPublicationIsDiscarded() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let location = makeEpochDummyPackage(label: "Trash-A").location
        let gate = LibraryEpochResultGate(UUID())
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository)

        let staleTrash = Task { @MainActor in
            try await store.moveToTrash(
                targetKind: .track,
                targetID: libraryA.trackID,
                location: location,
                operation: { _, _, _, _ in await gate.suspend() }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        let currentVersion = store.allTracksWindowContentVersion

        await gate.resume()
        try await staleTrash.value

        #expect(store.repository === libraryB.repository)
        #expect(store.tracks.map(\.title) == ["Library B"])
        #expect(store.allTracksWindowContentVersion == currentVersion)
    }
}

private func artworkPayload(
    track: LibraryTrackProjection,
    artworkID: UUID?
) -> LibraryArtworkPublicationPayload {
    let replacement = LibraryTrackProjection(
        id: track.id,
        title: track.title,
        artistID: track.artistID,
        artist: track.artist,
        albumID: track.albumID,
        album: track.album,
        duration: track.duration,
        year: track.year,
        codec: track.codec,
        sampleRate: track.sampleRate,
        channelCount: track.channelCount,
        bitDepth: track.bitDepth,
        isFavorite: track.isFavorite,
        isExplicit: track.isExplicit,
        customArtworkID: artworkID,
        artworkID: artworkID,
        relativeMediaPath: track.relativeMediaPath,
        lastPlayedAt: track.lastPlayedAt,
        hasSynchronizedLyrics: track.hasSynchronizedLyrics
    )
    return LibraryArtworkPublicationPayload(
        tracksByID: [track.id: replacement],
        albumsByID: [:],
        artistsByID: [:],
        playlistsByID: [:]
    )
}

@MainActor
struct LibraryStoreEpochErrorTests {
    @Test("A stale recent-play error cannot fail an attached library")
    func staleRecentlyPlayedErrorIsDiscarded() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryBDate = Date(timeIntervalSince1970: 200)
        let libraryB = try LibraryEpochFixture(
            title: "Library B",
            lastPlayedAt: libraryBDate
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        try await store.attach(repository: libraryA.repository)

        let gate = LibraryEpochResultGate(
            Result<LibraryRecentPlaybackResult, LibraryEpochTestError>.failure(
                .staleOperation
            )
        )
        let stalePlayback = Task { @MainActor in
            await store.recordRecentlyPlayed(
                trackID: libraryA.trackID,
                operation: { _, _, _ in
                    let result = await gate.suspend()
                    return try result.get()
                }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        await gate.resume()
        let succeeded = await stalePlayback.value
        #expect(!succeeded)

        #expect(store.repository === libraryB.repository)
        #expect(store.recentlyPlayedTracks.map(\.title) == ["Library B"])
        #expect(store.recentlyPlayedTracks.first?.lastPlayedAt == libraryBDate)
        #expect(store.operationFailure == nil)
    }

    @Test("A stale favorite failure is canceled for the attached library")
    func staleFavoriteErrorIsCanceled() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let gate = LibraryEpochResultGate(
            Result<LibraryTrackProjection, LibraryEpochTestError>.failure(
                .staleOperation
            )
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository)

        let staleFavorite = Task { @MainActor in
            try await store.setTrackFavorite(
                id: libraryA.trackID,
                isFavorite: true,
                operation: { _, _, _ in
                    try await gate.suspend().get()
                }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        await gate.resume()

        do {
            _ = try await staleFavorite.value
            Issue.record("Expected the superseded favorite operation to cancel")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(store.operationFailure == nil)
    }

    @Test("A stale lyric failure is canceled for the attached library")
    func staleLyricsErrorIsCanceled() async throws {
        let trackID = UUID()
        let libraryA = try LibraryEpochFixture(
            title: "Library A",
            trackID: trackID
        )
        let libraryB = try LibraryEpochFixture(
            title: "Library B",
            trackID: trackID
        )
        let packageA = makeEpochDummyPackage(label: "Lyrics-Error-A")
        let packageB = makeEpochDummyPackage(label: "Lyrics-Error-B")
        let gate = LibraryEpochResultGate(
            Result<ManagedLyricsSaveResult, LibraryEpochTestError>.failure(
                .staleOperation
            )
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository, package: packageA)

        let staleSave = Task { @MainActor in
            try await store.saveLyrics(
                LyricDocument(
                    trackID: trackID,
                    lines: [LyricLine(text: "Stale", startTime: 1)]
                ),
                operation: { _, _ in
                    try await gate.suspend().get()
                }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository, package: packageB)
        await store.loadInitialLibrary()
        await gate.resume()

        do {
            try await staleSave.value
            Issue.record("Expected the superseded lyric operation to cancel")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(store.operationFailure == nil)
    }

    @Test("A stale artwork failure is canceled for the attached library")
    func staleArtworkErrorIsCanceled() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let packageA = makeEpochDummyPackage(label: "Artwork-Error-A")
        let packageB = makeEpochDummyPackage(label: "Artwork-Error-B")
        let gate = LibraryEpochResultGate(
            Result<ManagedArtworkMutationResult, LibraryEpochTestError>.failure(
                .staleOperation
            )
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository, package: packageA)

        let staleArtwork = Task { @MainActor in
            try await store.setArtwork(
                ManagedArtworkEditRequest(
                    ownerKind: .track,
                    ownerID: libraryA.trackID,
                    data: Data([0]),
                    scale: 1,
                    normalizedOffset: .zero
                ),
                location: packageA.location,
                operation: { _, _ in
                    try await gate.suspend().get()
                }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository, package: packageB)
        await store.loadInitialLibrary()
        await gate.resume()

        do {
            _ = try await staleArtwork.value
            Issue.record("Expected the superseded artwork operation to cancel")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(store.operationFailure == nil)
    }

    @Test("A stale Trash failure is canceled for the attached library")
    func staleTrashErrorIsCanceled() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let location = makeEpochDummyPackage(label: "Trash-Error-A").location
        let gate = LibraryEpochResultGate(
            Result<UUID, LibraryEpochTestError>.failure(.staleOperation)
        )
        let store = LibraryStore()
        try await store.attach(repository: libraryA.repository)

        let staleTrash = Task { @MainActor in
            try await store.moveToTrash(
                targetKind: .track,
                targetID: libraryA.trackID,
                location: location,
                operation: { _, _, _, _ in
                    try await gate.suspend().get()
                }
            )
        }
        await gate.waitUntilSuspended()

        try await store.attach(repository: libraryB.repository)
        await store.loadInitialLibrary()
        await gate.resume()

        do {
            try await staleTrash.value
            Issue.record("Expected the superseded Trash operation to cancel")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(store.operationFailure == nil)
    }
}
