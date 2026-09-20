import Foundation

@MainActor
final class ManagedPlaybackTrackResolver: PlaybackTrackResolving {
    private let librarySession: LibrarySession
    private let fileManager: FileManager

    init(
        librarySession: LibrarySession,
        fileManager: FileManager = .default
    ) {
        self.librarySession = librarySession
        self.fileManager = fileManager
    }

    func resolve(
        trackIDs: [UUID]
    ) async throws -> [ResolvedPlaybackTrack] {
        guard let location = librarySession.location else {
            throw PlaybackFailure(
                trackID: trackIDs.first,
                message: "The Cadence library is not available."
            )
        }
        let repository: LibraryRepository
        do {
            repository = try librarySession.store.requireRepository()
        } catch {
            throw PlaybackFailure(
                trackID: trackIDs.first,
                message: error.localizedDescription
            )
        }

        let tracks = try await repository.playbackTracks(ids: trackIDs)
        var resolved: [ResolvedPlaybackTrack] = []
        for track in tracks {
            if let url = try? location.resolve(
                relativePath: track.relativeMediaPath,
                directoryHint: .notDirectory
            ),
                fileManager.fileExists(atPath: url.path) {
                resolved.append(
                    ResolvedPlaybackTrack(track: track, mediaURL: url)
                )
            }
        }
        let byID = Dictionary(
            uniqueKeysWithValues: resolved.map { ($0.track.id, $0) }
        )
        return trackIDs.compactMap { byID[$0] }
    }
}
