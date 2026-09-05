import Foundation
import OSLog

/// A content-addressed cache whose JSON index is the durable ownership record.
/// Downloads enter Staging, pass byte-count and SHA-256 checks, move to Objects,
/// and only then become visible through an atomically persisted index entry.
actor RemoteMediaCache {
    private static let maximumPrefetchTargets = 2

    private let rootURL: URL
    private let objectsURL: URL
    private let stagingURL: URL
    private let indexURL: URL
    private let provider: any RemoteLibraryProvider
    private let fileManager: FileManager
    var index: RemoteCacheIndex
    private var budgetBytes: Int64
    private var reservedBytes: Int64 = 0
    var pinnedIDs: Set<RemoteObjectID> = []
    var inFlight: [RemoteObjectID: Task<URL, Error>] = [:]
    var prefetchTasks: [RemoteObjectID: Task<Void, Never>] = [:]
    private let logger = Logger(
        subsystem: AppConfiguration.bundleIdentifier,
        category: "RemoteMediaCache"
    )

    init(
        rootURL: URL,
        budgetBytes: Int64,
        provider: any RemoteLibraryProvider,
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL
        objectsURL = rootURL.appending(
            path: "Objects",
            directoryHint: .isDirectory
        )
        stagingURL = rootURL.appending(
            path: "Staging",
            directoryHint: .isDirectory
        )
        indexURL = rootURL.appending(
            path: "CacheIndex.json",
            directoryHint: .notDirectory
        )
        self.budgetBytes = max(budgetBytes, 0)
        self.provider = provider
        self.fileManager = fileManager
        do {
            try fileManager.createDirectory(
                at: objectsURL,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: stagingURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw RemoteCacheError.directoryPreparationFailed(rootURL, error)
        }

        index = try RemoteCachePersistence.loadIndex(
            from: indexURL,
            fileManager: fileManager
        )
        try RemoteCachePersistence.removeAbandonedStagingFiles(
            at: stagingURL,
            fileManager: fileManager
        )
    }

    func localURL(
        for object: RemoteMediaObject
    ) async throws -> URL {
        try await materialize(object, protectedFromEviction: true)
    }

    func playableURL(
        for id: RemoteObjectID
    ) throws -> URL? {
        guard let entry = index[id] else {
            return nil
        }
        let url = rootURL.appending(
            path: entry.relativePath,
            directoryHint: .notDirectory
        )
        guard fileManager.fileExists(atPath: url.path) else {
            var updatedIndex = index
            updatedIndex[id] = nil
            try persist(updatedIndex)
            index = updatedIndex
            return nil
        }
        return url
    }

    func prefetch(
        _ object: RemoteMediaObject
    ) async {
        do {
            _ = try await materialize(object, protectedFromEviction: false)
        } catch is CancellationError {
            // Cancellation is expected when the queue's prefetch target changes.
        } catch {
            let description = error.localizedDescription
            logger.error(
                "Prefetch failed for \(object.id.rawValue, privacy: .private): \(description, privacy: .public)"
            )
        }
    }

    func replacePrefetchTargets(
        _ objects: [RemoteMediaObject]
    ) {
        let targets = Array(objects.prefix(Self.maximumPrefetchTargets))
        let targetIDs = Set(targets.map(\.id))
        for (id, task) in prefetchTasks where !targetIDs.contains(id) {
            task.cancel()
            prefetchTasks[id] = nil
        }
        for object in targets where prefetchTasks[object.id] == nil {
            prefetchTasks[object.id] = Task { [weak self] in
                await self?.prefetch(object)
                await self?.finishPrefetch(object.id)
            }
        }
    }

    func pin(
        _ ids: Set<RemoteObjectID>
    ) throws {
        let previous = pinnedIDs
        pinnedIDs = ids
        do {
            try enforceBudget(protectedID: nil)
        } catch {
            pinnedIDs = previous
            throw error
        }
    }

    func setBudget(
        bytes: Int64
    ) throws {
        let previous = budgetBytes
        budgetBytes = max(bytes, 0)
        do {
            try enforceBudget(protectedID: nil)
        } catch {
            budgetBytes = previous
            throw error
        }
    }
}

extension RemoteMediaCache {
    private func materialize(
        _ object: RemoteMediaObject,
        protectedFromEviction: Bool
    ) async throws -> URL {
        try object.validate()
        if let cached = try validCachedURL(for: object) {
            try touch(object.id)
            return cached
        }
        if let task = inFlight[object.id] {
            return try await task.value
        }

        try reserveSpace(for: object)
        let task = Task<URL, Error> {
            try await self.downloadAndPromote(object)
        }
        inFlight[object.id] = task
        var holdsReservation = true
        defer {
            inFlight[object.id] = nil
            if holdsReservation {
                releaseSpace(for: object)
            }
        }
        let url = try await task.value
        releaseSpace(for: object)
        holdsReservation = false
        try enforceBudget(
            protectedID: protectedFromEviction ? object.id : nil
        )
        guard try playableURL(for: object.id) != nil else {
            throw RemoteProviderError.serviceUnavailable(
                "The object exceeds the available cache budget."
            )
        }
        return url
    }

    private func downloadAndPromote(
        _ object: RemoteMediaObject
    ) async throws -> URL {
        let stagedURL = stagingURL.appending(
            path: "\(UUID().uuidString).partial",
            directoryHint: .notDirectory
        )
        guard fileManager.createFile(
            atPath: stagedURL.path,
            contents: nil
        ) else {
            throw RemoteProviderError.serviceUnavailable(
                "The cache staging file could not be created."
            )
        }
        let relativePath = "Objects/\(object.sha256).\(object.fileExtension)"
        let destinationURL = rootURL.appending(
            path: relativePath,
            directoryHint: .notDirectory
        )
        let destinationExisted = fileManager.fileExists(
            atPath: destinationURL.path
        )
        do {
            try await RemoteMediaCacheDownload.writeVerified(object, from: provider, to: stagedURL)
            if !destinationExisted {
                try fileManager.moveItem(at: stagedURL, to: destinationURL)
            }
            var updatedIndex = index
            updatedIndex[object.id] = RemoteCacheEntry(
                object: object,
                relativePath: relativePath,
                lastAccessedAt: Date()
            )
            try persist(updatedIndex)
            index = updatedIndex
        } catch {
            try RemoteCachePersistence.rollbackPromotion(
                destinationExisted: destinationExisted,
                destinationURL: destinationURL,
                stagedURL: stagedURL,
                fileManager: fileManager,
                primaryError: error
            )
            throw error
        }
        try RemoteCachePersistence.removeStagedFileIfPresent(
            stagedURL,
            fileManager: fileManager,
            primaryError: nil
        )
        return destinationURL
    }

    private func reserveSpace(
        for object: RemoteMediaObject
    ) throws {
        guard object.byteCount <= budgetBytes else {
            throw RemoteProviderError.serviceUnavailable(
                "The object exceeds the available cache budget."
            )
        }
        try enforceBudget(
            protectedID: nil,
            reservingBytes: object.byteCount
        )
        reservedBytes += object.byteCount
    }

    private func releaseSpace(
        for object: RemoteMediaObject
    ) {
        reservedBytes = max(reservedBytes - object.byteCount, 0)
    }

    private func validCachedURL(
        for object: RemoteMediaObject
    ) throws -> URL? {
        guard let entry = index[object.id],
              entry.object == object
        else {
            try removeEntry(for: object.id)
            return nil
        }
        let url = rootURL.appending(
            path: entry.relativePath,
            directoryHint: .notDirectory
        )
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey])
        } catch {
            try removeEntry(for: object.id)
            throw RemoteCacheError.objectInspectionFailed(url, error)
        }
        guard Int64(values.fileSize ?? -1) == object.byteCount else {
            try removeEntry(for: object.id)
            return nil
        }
        return url
    }

    private func touch(
        _ id: RemoteObjectID
    ) throws {
        guard var entry = index[id] else {
            return
        }
        entry.lastAccessedAt = Date()
        var updatedIndex = index
        updatedIndex[id] = entry
        try persist(updatedIndex)
        index = updatedIndex
    }

    private func enforceBudget(
        protectedID: RemoteObjectID?,
        reservingBytes: Int64 = 0
    ) throws {
        let plan = try RemoteCacheEvictionPlan.make(
            index: index,
            pinnedIDs: pinnedIDs,
            protectedID: protectedID,
            reservedBytes: reservedBytes + reservingBytes,
            budgetBytes: budgetBytes
        )
        guard !plan.evictedEntries.isEmpty else {
            return
        }
        // Commit the ownership change before deleting bytes. A deletion failure
        // may leave reclaimable data, but can never leave an index pointing at
        // an object already removed by eviction.
        try persist(plan.index)
        index = plan.index
        for entry in plan.evictedEntries {
            try removeObjectFileIfUnshared(entry)
        }
    }

    private func removeEntry(
        for id: RemoteObjectID
    ) throws {
        guard let entry = index[id] else {
            return
        }
        var updatedIndex = index
        updatedIndex[id] = nil
        try persist(updatedIndex)
        index = updatedIndex
        try removeObjectFileIfUnshared(entry)
    }

    func persist(_ updatedIndex: RemoteCacheIndex) throws {
        do {
            let data = try JSONEncoder().encode(updatedIndex)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            throw RemoteCacheError.indexPersistenceFailed(indexURL, error)
        }
    }

    func removeObjectFileIfUnshared(
        _ entry: RemoteCacheEntry
    ) throws {
        let sharedByAnotherEntry = index.entries.contains {
            $0.relativePath == entry.relativePath
        }
        guard !sharedByAnotherEntry else {
            return
        }
        let url = rootURL.appending(
            path: entry.relativePath,
            directoryHint: .notDirectory
        )
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw RemoteCacheError.objectRemovalFailed(url, error)
        }
    }

    private func finishPrefetch(
        _ id: RemoteObjectID
    ) {
        prefetchTasks[id] = nil
    }
}
