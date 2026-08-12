import Foundation

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
        let externalTracks = external.resolvedTracks(ids: trackIDs)
        let externalIDs = Set(externalTracks.map(\.track.id))
        let managedIDs = trackIDs.filter { !externalIDs.contains($0) }
        let managedTracks: [ResolvedPlaybackTrack] = if managedIDs.isEmpty {
            []
        } else {
            try await managed.resolve(trackIDs: managedIDs)
        }
        let tracksByID = Dictionary(
            uniqueKeysWithValues: (externalTracks + managedTracks).map {
                ($0.track.id, $0)
            }
        )
        return trackIDs.compactMap { tracksByID[$0] }
    }
}
