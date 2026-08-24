import Foundation

struct ArtworkMetadataLoader: Sendable {
    let load: @Sendable (
        _ repository: LibraryRepository,
        _ id: UUID
    ) async throws -> ManagedArtworkProjection?

    static let live = ArtworkMetadataLoader { repository, id in
        try await repository.artwork(id: id)
    }
}

struct ArtworkMetadataLoadEntry {
    let token: UUID
    let task: Task<ManagedArtworkProjection?, Error>
    var waiterIDs: Set<UUID>

    func cancel() {
        task.cancel()
    }
}

struct ArtworkDataLoader: Sendable {
    let load: @Sendable (URL) throws -> Data

    static let live = ArtworkDataLoader { url in
        try Data(
            contentsOf: url,
            options: [.mappedIfSafe]
        )
    }
}

struct ArtworkDataLoadEntry {
    let token: UUID
    let task: Task<Data, Error>
    var waiterIDs: Set<UUID>

    func cancel() {
        task.cancel()
    }
}

private struct ArtworkLookupRequest {
    let id: UUID
    let location: ManagedLibraryLocation
    let variant: ArtworkAssetVariant
    let metadataLoader: ArtworkMetadataLoader
    let dataLoader: ArtworkDataLoader
    let context: LibraryStoreContext
    let generation: UInt64
}

extension LibraryStore {
    func artworkAsset(
        id: UUID,
        location: ManagedLibraryLocation?,
        variant: ArtworkAssetVariant = .thumbnail,
        metadataLoader: ArtworkMetadataLoader = .live,
        dataLoader: ArtworkDataLoader = .live
    ) async -> ArtworkAsset? {
        guard let location else {
            return nil
        }
        let request = ArtworkLookupRequest(
            id: id,
            location: location,
            variant: variant,
            metadataLoader: metadataLoader,
            dataLoader: dataLoader,
            context: captureLibraryContext(),
            generation: artworkLookupGenerations[id] ?? 0
        )
        do {
            return try await loadArtworkAsset(request)
        } catch is CancellationError {
            return nil
        } catch {
            guard !Task.isCancelled, ownsArtworkLookup(request) else {
                return nil
            }
            recordOperationFailure(.artworkLoad, error: error)
            return nil
        }
    }

    private func loadArtworkAsset(
        _ request: ArtworkLookupRequest
    ) async throws -> ArtworkAsset? {
        try requireCurrentArtworkLookup(request)
        let repository = try requireRepository()
        try requireCurrentArtworkLookup(request)
        guard let artwork = try await artworkMetadata(
            for: request,
            repository: repository
        ) else {
            return nil
        }
        try requireCurrentArtworkLookup(request)
        if let cached = artworkAssetCache.asset(
            id: request.id,
            revision: artwork.revision,
            variant: request.variant
        ) {
            return cached
        }
        let url = try request.location.resolve(
            relativePath: artwork.relativePath
        )
        let key = ArtworkAssetCache.Key(
            id: request.id,
            revision: artwork.revision,
            variant: request.variant
        )
        let data = try await artworkData(
            at: url,
            key: key,
            dataLoader: request.dataLoader
        )
        try requireCurrentArtworkLookup(request)
        guard !data.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let asset = ArtworkAsset(
            id: artwork.id,
            revision: artwork.revision,
            data: data,
            variant: request.variant,
            scale: artwork.scale,
            normalizedOffset: CGSize(
                width: artwork.normalizedOffsetX,
                height: artwork.normalizedOffsetY
            )
        )
        try requireCurrentArtworkLookup(request)
        artworkAssetCache.insert(asset, variant: request.variant)
        return asset
    }

    private func artworkMetadata(
        for request: ArtworkLookupRequest,
        repository: LibraryRepository
    ) async throws -> ManagedArtworkProjection? {
        if let cached = artworkMetadataResults.result(
            id: request.id,
            epoch: request.context.epoch
        ) {
            return cached.artwork
        }
        let waiterID = UUID()
        let entry = acquireArtworkMetadataLoad(
            id: request.id,
            repository: repository,
            metadataLoader: request.metadataLoader,
            waiterID: waiterID
        )
        let token = entry.token
        let metadataLoad = entry.task
        return try await withTaskCancellationHandler {
            defer {
                releaseArtworkMetadataWaiter(
                    waiterID,
                    id: request.id,
                    token: token,
                    cancelProducerIfLast: false
                )
            }
            do {
                let artwork = try await metadataLoad.value
                try requireCurrentArtworkMetadataLoad(request, token: token)
                artworkMetadataResults.insert(
                    ArtworkMetadataResultEntry(
                        epoch: request.context.epoch,
                        artwork: artwork
                    ),
                    id: request.id
                )
                return artwork
            } catch {
                try requireCurrentArtworkMetadataLoad(request, token: token)
                throw error
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.releaseArtworkMetadataWaiter(
                    waiterID,
                    id: request.id,
                    token: token,
                    cancelProducerIfLast: true
                )
            }
        }
    }

    private func acquireArtworkMetadataLoad(
        id: UUID,
        repository: LibraryRepository,
        metadataLoader: ArtworkMetadataLoader,
        waiterID: UUID
    ) -> ArtworkMetadataLoadEntry {
        if var existing = artworkMetadataLoads[id] {
            existing.waiterIDs.insert(waiterID)
            artworkMetadataLoads[id] = existing
            return existing
        }
        let created = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            do {
                let artwork = try await metadataLoader.load(repository, id)
                try Task.checkCancellation()
                return artwork
            } catch {
                try Task.checkCancellation()
                throw error
            }
        }
        let entry = ArtworkMetadataLoadEntry(
            token: UUID(),
            task: created,
            waiterIDs: [waiterID]
        )
        artworkMetadataLoads[id] = entry
        return entry
    }

    private func releaseArtworkMetadataWaiter(
        _ waiterID: UUID,
        id: UUID,
        token: UUID,
        cancelProducerIfLast: Bool
    ) {
        guard var entry = artworkMetadataLoads[id],
              entry.token == token,
              entry.waiterIDs.remove(waiterID) != nil else {
            return
        }
        guard entry.waiterIDs.isEmpty else {
            artworkMetadataLoads[id] = entry
            return
        }
        artworkMetadataLoads[id] = nil
        if cancelProducerIfLast {
            entry.cancel()
        }
    }

    private func ownsArtworkMetadataLoad(
        _ request: ArtworkLookupRequest,
        token: UUID
    ) -> Bool {
        ownsArtworkLookup(request)
            && artworkMetadataLoads[request.id]?.token == token
    }

    private func requireCurrentArtworkMetadataLoad(
        _ request: ArtworkLookupRequest,
        token: UUID
    ) throws {
        try Task.checkCancellation()
        guard ownsArtworkMetadataLoad(request, token: token) else {
            throw CancellationError()
        }
    }

    private func ownsArtworkLookup(_ request: ArtworkLookupRequest) -> Bool {
        isCurrentLibraryContext(request.context)
            && (artworkLookupGenerations[request.id] ?? 0)
            == request.generation
    }

    private func requireCurrentArtworkLookup(
        _ request: ArtworkLookupRequest
    ) throws {
        try Task.checkCancellation()
        guard ownsArtworkLookup(request) else {
            throw CancellationError()
        }
    }

    private func artworkData(
        at url: URL,
        key: ArtworkAssetCache.Key,
        dataLoader: ArtworkDataLoader
    ) async throws -> Data {
        let waiterID = UUID()
        let entry = acquireArtworkDataLoad(
            at: url,
            key: key,
            dataLoader: dataLoader,
            waiterID: waiterID
        )
        let token = entry.token
        let dataLoad = entry.task
        return try await withTaskCancellationHandler {
            defer {
                releaseArtworkDataWaiter(
                    waiterID,
                    key: key,
                    token: token,
                    cancelProducerIfLast: false
                )
            }
            do {
                let data = try await dataLoad.value
                try Task.checkCancellation()
                return data
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.releaseArtworkDataWaiter(
                    waiterID,
                    key: key,
                    token: token,
                    cancelProducerIfLast: true
                )
            }
        }
    }

    private func acquireArtworkDataLoad(
        at url: URL,
        key: ArtworkAssetCache.Key,
        dataLoader: ArtworkDataLoader,
        waiterID: UUID
    ) -> ArtworkDataLoadEntry {
        if var existing = artworkDataLoads[key] {
            existing.waiterIDs.insert(waiterID)
            artworkDataLoads[key] = existing
            return existing
        }
        let created = Task.detached(priority: .utility) { () throws -> Data in
            try Task.checkCancellation()
            do {
                let data = try dataLoader.load(url)
                try Task.checkCancellation()
                return data
            } catch {
                try Task.checkCancellation()
                throw error
            }
        }
        let entry = ArtworkDataLoadEntry(
            token: UUID(),
            task: created,
            waiterIDs: [waiterID]
        )
        artworkDataLoads[key] = entry
        return entry
    }

    private func releaseArtworkDataWaiter(
        _ waiterID: UUID,
        key: ArtworkAssetCache.Key,
        token: UUID,
        cancelProducerIfLast: Bool
    ) {
        guard var entry = artworkDataLoads[key],
              entry.token == token,
              entry.waiterIDs.remove(waiterID) != nil else {
            return
        }
        guard entry.waiterIDs.isEmpty else {
            artworkDataLoads[key] = entry
            return
        }
        artworkDataLoads[key] = nil
        if cancelProducerIfLast {
            entry.cancel()
        }
    }
}
