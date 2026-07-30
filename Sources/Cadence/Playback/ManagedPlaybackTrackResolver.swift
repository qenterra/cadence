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
        guard
            let repository = librarySession.store.repository,
            let location = librarySession.location
        else {
            throw PlaybackFailure(
                trackID: trackIDs.first,
                message: "The Cadence library is not available."
            )
        }

        let tracks = try await repository.playbackTracks(ids: trackIDs)
        return tracks.compactMap { track in
            guard
                let url = try? location.resolve(
                    relativePath: track.relativeMediaPath,
                    directoryHint: .notDirectory
                ),
                fileManager.fileExists(atPath: url.path)
            else {
                return nil
            }
            return ResolvedPlaybackTrack(
                track: track,
                mediaURL: url
            )
        }
    }
}
