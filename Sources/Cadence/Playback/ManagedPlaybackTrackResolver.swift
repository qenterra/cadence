import Foundation

@MainActor
final class ManagedPlaybackTrackResolver: PlaybackTrackResolving {
    private let librarySession: LibrarySession
    private let fileManager: FileManager
    private let remoteSource: RemotePlaybackSource?
    private let cloudMediaSourceRegistry: CloudMediaPlaybackSourceRegistry
    private let mediaMaterializer: any MediaMaterializing

    init(
        librarySession: LibrarySession,
        remoteSource: RemotePlaybackSource? = nil,
        cloudMediaSource: CloudMediaPlaybackSource? = nil,
        cloudMediaSourceRegistry: CloudMediaPlaybackSourceRegistry? = nil,
        fileManager: FileManager = .default,
        mediaMaterializer: any MediaMaterializing = UbiquitousMediaMaterializer()
    ) {
        self.librarySession = librarySession
        self.remoteSource = remoteSource
        self.cloudMediaSourceRegistry = cloudMediaSourceRegistry
            ?? CloudMediaPlaybackSourceRegistry(source: cloudMediaSource)
        self.fileManager = fileManager
        self.mediaMaterializer = mediaMaterializer
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
        var missing: [PlaybackTrack] = []
        for track in tracks {
            if let url = try? location.resolve(
                relativePath: track.relativeMediaPath,
                directoryHint: .notDirectory
            ),
                fileManager.fileExists(atPath: url.path) {
                try await mediaMaterializer.materialize(url)
                resolved.append(
                    ResolvedPlaybackTrack(track: track, mediaURL: url)
                )
            } else {
                missing.append(track)
            }
        }
        if let cloudMediaSource = cloudMediaSourceRegistry.source,
           !missing.isEmpty {
            let cloudURLs = try await cloudMediaSource.resolve(tracks: missing)
            resolved.append(contentsOf: missing.compactMap { track in
                cloudURLs[track.id].map {
                    ResolvedPlaybackTrack(track: track, mediaURL: $0)
                }
            })
        }
        let resolvedIDs = Set(resolved.map(\.track.id))
        let stillMissing = missing.filter { !resolvedIDs.contains($0.id) }
        if let remoteSource,
           !stillMissing.isEmpty {
            let remoteURLs = try await remoteSource.resolve(
                trackIDs: stillMissing.map(\.id)
            )
            resolved.append(contentsOf: stillMissing.compactMap { track in
                remoteURLs[track.id].map {
                    ResolvedPlaybackTrack(track: track, mediaURL: $0)
                }
            })
        }
        let byID = Dictionary(
            uniqueKeysWithValues: resolved.map { ($0.track.id, $0) }
        )
        return trackIDs.compactMap { byID[$0] }
    }
}
