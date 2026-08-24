@testable import Cadence
import Foundation
import Testing

struct ManagedRecoveryOutcomeTests {
    @Test("Lyric save failure preserves effects committed by recovery")
    func lyricFailureCarriesCommittedRecovery() async throws {
        let fixture = try ManagedLyricsFixture(trackCount: 2)
        defer { fixture.remove() }
        let savedTrackID = try #require(fixture.additionalTrackIDs.first)
        let operationID = try #require(
            UUID(uuidString: "10000000-0000-0000-0000-000000000001")
        )
        try installLyricRecovery(fixture, operationID: operationID)

        let caughtError: any Error
        do {
            try await fixture.service.save(
                LyricDocument(
                    trackID: savedTrackID,
                    lines: [LyricLine(text: "Invalid B", startTime: 181)]
                )
            )
            Issue.record("Expected the invalid current save to fail")
            return
        } catch {
            caughtError = error
        }

        let semanticError = (caughtError as? any ManagedLyricsRecoveryCarryingError)?
            .underlyingError ?? caughtError
        #expect(
            semanticError as? ManagedLyricsServiceError
                == .invalidDocument("Time exceeds the track duration.")
        )
        #expect(
            try await fixture.repository.lyricMetadata(trackID: fixture.trackID)?
                .timingStatus == .synchronized
        )
        #expect(
            try await fixture.repository.lyricMetadata(trackID: savedTrackID)
                == nil
        )
        #expect(try await fixture.service.recover() == .empty)
        let carrier = try #require(
            caughtError as? any ManagedLyricsRecoveryCarryingError
        )
        #expect(
            carrier.recovery
                == ManagedLyricsRecoveryResult(
                    recoveredOperationIDs: [operationID],
                    rolledBackOperationIDs: [],
                    affectedTrackIDs: [fixture.trackID]
                )
        )
        #expect(
            carrier.underlyingError as? ManagedLyricsServiceError
                == .invalidDocument("Time exceeds the track duration.")
        )
    }

    @Test("Artwork edit failure preserves effects committed by recovery")
    func artworkFailureCarriesCommittedRecovery() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let operationID = try #require(
            UUID(uuidString: "20000000-0000-0000-0000-000000000001")
        )
        let artworkID = try #require(
            UUID(uuidString: "20000000-0000-0000-0000-000000000002")
        )
        try installArtworkRecovery(
            fixture,
            operationID: operationID,
            artworkID: artworkID
        )

        let caughtError: any Error
        do {
            try await fixture.service.setArtwork(
                invalidArtworkRequest(ownerID: fixture.artistID)
            )
            Issue.record("Expected the invalid current edit to fail")
            return
        } catch {
            caughtError = error
        }

        let semanticError = (
            caughtError as? any ManagedArtworkRecoveryCarryingError
        )?.underlyingError ?? caughtError
        #expect(semanticError as? ManagedArtworkEditError == .invalidImage)
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == artworkID
        )
        #expect(
            try await fixture.repository.artworkEditSnapshot(
                ownerKind: .artist,
                ownerID: fixture.artistID
            ) == nil
        )
        #expect(try await fixture.service.recover() == .empty)
        try expectArtworkCarrier(
            caughtError,
            operationID: operationID,
            ownerID: fixture.albumID,
            artworkID: artworkID
        )
    }

    private func installLyricRecovery(
        _ fixture: ManagedLyricsFixture,
        operationID: UUID
    ) throws {
        let data = Data("[00:01.000]Recovered A\n".utf8)
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

    private func installArtworkRecovery(
        _ fixture: ManagedArtworkFixture,
        operationID: UUID,
        artworkID: UUID
    ) throws {
        let manifest = try fixture.manifest(
            state: .fileInstalled,
            operationID: operationID,
            artworkID: artworkID
        )
        try fixture.installNewFile(for: manifest)
        try fixture.store.save(manifest)
    }

    private func invalidArtworkRequest(
        ownerID: UUID
    ) -> ManagedArtworkEditRequest {
        ManagedArtworkEditRequest(
            ownerKind: .artist,
            ownerID: ownerID,
            data: Data("Invalid B".utf8),
            scale: 1,
            normalizedOffset: .zero
        )
    }

    private func expectArtworkCarrier(
        _ error: any Error,
        operationID: UUID,
        ownerID: UUID,
        artworkID: UUID
    ) throws {
        let carrier = try #require(
            error as? any ManagedArtworkRecoveryCarryingError
        )
        #expect(
            carrier.recovery
                == ManagedArtworkRecoveryResult(
                    recoveredOperationIDs: [operationID],
                    rolledBackOperationIDs: [],
                    effects: [
                        ManagedArtworkPublicationEffect(
                            ownerKind: .album,
                            ownerID: ownerID,
                            previousArtworkID: nil,
                            newArtworkID: artworkID
                        ),
                    ]
                )
        )
        #expect(
            carrier.underlyingError as? ManagedArtworkEditError == .invalidImage
        )
    }
}
