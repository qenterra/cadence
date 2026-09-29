import Foundation

enum PlaybackTrackResolution {
    static func orderedUniqueIDs(_ trackIDs: [UUID]) -> [UUID] {
        var seenIDs: Set<UUID> = []
        return trackIDs.filter { seenIDs.insert($0).inserted }
    }

    static func index(
        _ tracks: [ResolvedPlaybackTrack]
    ) -> [UUID: ResolvedPlaybackTrack] {
        tracks.reduce(into: [:]) { result, track in
            if result[track.track.id] == nil {
                result[track.track.id] = track
            }
        }
    }
}

@MainActor
final class CompositePlaybackTrackResolver: PlaybackTrackResolving {
    private let external: ExternalAudioSession
    private let managed: any PlaybackTrackResolving

    init(
        external: ExternalAudioSession,
        managed: any PlaybackTrackResolving
    ) {
        self.external = external
        self.managed = managed
    }

    func resolve(
        trackIDs: [UUID]
    ) async throws -> [ResolvedPlaybackTrack] {
        let requestedIDs = PlaybackTrackResolution.orderedUniqueIDs(trackIDs)
        let externalTracks = external.resolvedTracks(ids: requestedIDs)
        let externalIDs = Set(externalTracks.map(\.track.id))
        let managedIDs = requestedIDs.filter { !externalIDs.contains($0) }
        let managedTracks: [ResolvedPlaybackTrack] = if managedIDs.isEmpty {
            []
        } else {
            try await managed.resolve(trackIDs: managedIDs)
        }
        let tracksByID = PlaybackTrackResolution.index(
            externalTracks + managedTracks
        )
        return requestedIDs.compactMap { tracksByID[$0] }
    }
}
