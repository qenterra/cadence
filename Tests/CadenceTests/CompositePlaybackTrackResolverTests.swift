@testable import Cadence
import Foundation
import Testing

@MainActor
struct CompositePlaybackTrackResolverTests {
    @Test("External IDs resolve locally while managed IDs preserve request order")
    func mixedResolution() async throws {
        let externalResolved = playbackTestTrack(
            id: UUID(),
            title: "External"
        )
        let managedResolved = playbackTestTrack(
            id: UUID(),
            title: "Managed"
        )
        let externalSession = ExternalAudioSession()
        externalSession.replace(
            with: [
                ExternalAudioItem(
                    id: externalResolved.track.id,
                    sourceURL: externalResolved.mediaURL,
                    resolvedTrack: externalResolved,
                    artwork: nil
                ),
            ]
        )
        let managed = PlaybackTestResolver(tracks: [managedResolved])
        let resolver = CompositePlaybackTrackResolver(
            external: externalSession,
            managed: managed
        )

        let resolved = try await resolver.resolve(
            trackIDs: [managedResolved.track.id, externalResolved.track.id]
        )

        #expect(
            resolved.map(\.track.id) == [
                managedResolved.track.id,
                externalResolved.track.id,
            ]
        )
        #expect(managed.requests == [[managedResolved.track.id]])
    }

    @Test("Missing managed IDs remain absent")
    func missingManagedID() async throws {
        let missingID = UUID()
        let managed = PlaybackTestResolver(tracks: [])
        let resolver = CompositePlaybackTrackResolver(
            external: ExternalAudioSession(),
            managed: managed
        )

        let resolved = try await resolver.resolve(trackIDs: [missingID])

        #expect(resolved.isEmpty)
        #expect(managed.requests == [[missingID]])
    }
}
