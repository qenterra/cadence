@testable import Cadence
import Foundation
import Testing

// swiftlint:disable type_name
@MainActor
struct LibraryStoreRecoveryFailurePublicationTests {
    @Test("Lyric recovery publishes before the current save error")
    func lyricsRecoveryPublishesBeforeCurrentFailure() async throws {
        let context = try await LyricsRecoveryStoreContext.make()
        let caughtError = try #require(
            await captureRecoveryTestError {
                try await context.store.saveLyrics(context.invalidDocument)
            }
        )

        #expect(
            caughtError as? ManagedLyricsServiceError
                == .invalidDocument("Time exceeds the track duration.")
        )
        #expect(
            context.window.track(at: context.recoveredIndex)?
                .hasSynchronizedLyrics == true
        )
        #expect(
            context.window.track(at: context.failedIndex)?
                .hasSynchronizedLyrics == false
        )
        #expect(context.window.revision == context.initialRevision + 1)
        #expect(context.store.lyricsSearchIndexState == .ready)
        let firstMatches = await context.recoveredMatches()
        #expect(firstMatches.map(\.track.id) == [context.fixture.trackID])
        #expect(try await context.fixture.service.recover() == .empty)

        let publishedRevision = context.window.revision
        await #expect(throws: context.expectedError) {
            try await context.store.saveLyrics(context.invalidDocument)
        }
        let repeatedMatches = await context.recoveredMatches()

        #expect(context.window.revision == publishedRevision)
        #expect(repeatedMatches.map(\.track.id) == [context.fixture.trackID])
        try await context.remove()
    }

    @Test("Artwork recovery publishes before the current edit error")
    func artworkRecoveryPublishesBeforeCurrentFailure() async throws {
        let context = try await ArtworkRecoveryStoreContext.make()
        let caughtError = try #require(
            await captureRecoveryTestError {
                _ = try await context.store.setArtwork(
                    context.invalidRequest,
                    location: context.fixture.location
                )
            }
        )
        await context.configureWindow()

        #expect(caughtError as? ManagedArtworkEditError == .invalidImage)
        #expect(context.window.track(at: 0)?.artworkID == context.artworkID)
        #expect(context.window.revision == context.initialWindowRevision + 1)
        #expect(
            context.store.allTracksWindowContentVersion.sourceID
                == context.initialContentVersion.sourceID
        )
        #expect(
            context.store.allTracksWindowContentVersion.generation
                == context.initialContentVersion.generation + 1
        )
        #expect(context.recoveredCachedAsset() == nil)
        #expect(context.sentinelCachedAsset() == context.sentinelAsset)
        #expect(
            try await context.fixture.repository.artworkEditSnapshot(
                ownerKind: .artist,
                ownerID: context.fixture.artistID
            ) == nil
        )
        #expect(try await context.fixture.service.recover() == .empty)

        let publishedVersion = context.store.allTracksWindowContentVersion
        context.store.artworkAssetCache.insert(context.recoveredAsset)
        await #expect(throws: ManagedArtworkEditError.invalidImage) {
            _ = try await context.store.setArtwork(
                context.invalidRequest,
                location: context.fixture.location
            )
        }

        #expect(context.store.allTracksWindowContentVersion == publishedVersion)
        #expect(context.recoveredCachedAsset() == context.recoveredAsset)
        #expect(context.sentinelCachedAsset() == context.sentinelAsset)
        try await context.remove()
    }
}

// swiftlint:enable type_name

@MainActor
struct LibraryStoreRecoveryFailureEpochTests {
    @Test("A stale lyric recovery failure publishes nothing")
    func staleLyricsRecoveryFailurePublishesNothing() async throws {
        let context = try await StaleLyricsStoreContext.make()
        await context.gate.resume()

        do {
            try await context.task.value
            Issue.record("Expected the stale lyric recovery to cancel")
        } catch {
            #expect(error is CancellationError)
        }

        #expect(context.store.repository === context.libraryB.repository)
        #expect(context.store.tracks.map(\.title) == ["Library B"])
        #expect(context.store.tracks.first?.hasSynchronizedLyrics == false)
        #expect(context.window.track(at: 0)?.title == "Library B")
        #expect(context.window.track(at: 0)?.hasSynchronizedLyrics == false)
        #expect(context.window.revision == context.initialWindowRevision)
        #expect(
            context.store.allTracksWindowContentVersion
                == context.initialContentVersion
        )
    }

    @Test("A stale artwork recovery failure publishes nothing")
    func staleArtworkRecoveryFailurePublishesNothing() async throws {
        let context = try await StaleArtworkStoreContext.make()
        await context.gate.resume()

        do {
            _ = try await context.task.value
            Issue.record("Expected the stale artwork recovery to cancel")
        } catch {
            #expect(error is CancellationError)
        }

        #expect(context.store.repository === context.libraryB.repository)
        #expect(context.store.tracks.map(\.title) == ["Library B"])
        #expect(context.window.track(at: 0)?.title == "Library B")
        #expect(context.window.track(at: 0)?.artworkID == nil)
        #expect(context.window.revision == context.initialWindowRevision)
        #expect(
            context.store.allTracksWindowContentVersion
                == context.initialContentVersion
        )
        #expect(context.cachedSentinel() == context.sentinelAsset)
    }
}
