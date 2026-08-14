import Foundation

actor RemotePlaybackSource {
    private var objectsByTrackID: [UUID: RemoteMediaObject] = [:]
    private var cache: RemoteMediaCache?

    func activate(
        provider: any RemoteLibraryProvider,
        manifest: RemoteLibraryManifest,
        cacheRootURL: URL,
        budgetBytes: Int64
    ) async throws {
        try manifest.validate()
        objectsByTrackID = Dictionary(
            uniqueKeysWithValues: manifest.tracks.map {
                ($0.trackID, $0.media)
            }
        )
        cache = try RemoteMediaCache(
            rootURL: cacheRootURL,
            budgetBytes: budgetBytes,
            provider: provider
        )
    }

    func deactivate() {
        objectsByTrackID.removeAll()
        cache = nil
    }

    func resolve(
        trackIDs: [UUID]
    ) async throws -> [UUID: URL] {
        guard let cache else {
            throw RemoteProviderError.serviceUnavailable(
                "The remote library is not connected."
            )
        }
        let objects = trackIDs.compactMap { id in
            objectsByTrackID[id].map { (id, $0) }
        }
        try await cache.pin(Set(objects.prefix(2).map(\.1.id)))
        guard let current = objects.first else {
            return [:]
        }

        var result: [UUID: URL] = [:]
        result[current.0] = try await cache.localURL(for: current.1)
        let following = Array(objects.dropFirst())
        for (trackID, object) in following {
            if let url = try await cache.playableURL(for: object.id) {
                result[trackID] = url
            }
        }
        await cache.replacePrefetchTargets(following.map(\.1))
        return result
    }

    func setCacheBudget(
        _ bytes: Int64
    ) async throws {
        guard let cache else {
            throw RemoteProviderError.serviceUnavailable(
                "The remote library cache is not active."
            )
        }
        try await cache.setBudget(bytes: bytes)
    }
}
