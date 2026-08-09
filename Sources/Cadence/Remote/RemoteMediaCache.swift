import Foundation

actor RemoteMediaCache {
    private let rootURL: URL
    private let objectsURL: URL
    private let stagingURL: URL
    private let indexURL: URL
    private let provider: any RemoteLibraryProvider
    private let fileManager: FileManager
    private var index: RemoteCacheIndex
    private var budgetBytes: Int64
    private var pinnedIDs: Set<RemoteObjectID> = []
    private var inFlight: [RemoteObjectID: Task<URL, Error>] = [:]
    private var prefetchTasks: [RemoteObjectID: Task<Void, Never>] = [:]

    init(
        rootURL: URL,
        budgetBytes: Int64,
        provider: any RemoteLibraryProvider,
        fileManager: FileManager = .default
    ) {
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
        index = Self.loadIndex(from: indexURL)

        try? fileManager.createDirectory(
            at: objectsURL,
            withIntermediateDirectories: true
        )
        try? fileManager.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: true
        )
        Self.removeAbandonedStagingFiles(
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
    ) -> URL? {
        guard let entry = index[id] else {
            return nil
        }
        let url = rootURL.appending(
            path: entry.relativePath,
            directoryHint: .notDirectory
        )
        guard fileManager.fileExists(atPath: url.path) else {
            index[id] = nil
            try? saveIndex()
            return nil
        }
        return url
    }

    func prefetch(
        _ object: RemoteMediaObject
    ) async {
        _ = try? await materialize(object, protectedFromEviction: false)
    }

    func replacePrefetchTargets(
        _ objects: [RemoteMediaObject]
    ) {
        let targetIDs = Set(objects.map(\.id))
        for (id, task) in prefetchTasks where !targetIDs.contains(id) {
            task.cancel()
            prefetchTasks[id] = nil
        }
        for object in objects where prefetchTasks[object.id] == nil {
            prefetchTasks[object.id] = Task { [weak self] in
                await self?.prefetch(object)
                await self?.finishPrefetch(object.id)
            }
        }
    }

    func pin(
        _ ids: Set<RemoteObjectID>
    ) {
        pinnedIDs = ids
        try? enforceBudget(protectedID: nil)
    }

    func setBudget(
        bytes: Int64
    ) {
        budgetBytes = max(bytes, 0)
        try? enforceBudget(protectedID: nil)
    }
}

private extension RemoteMediaCache {
    func materialize(
        _ object: RemoteMediaObject,
        protectedFromEviction: Bool
    ) async throws -> URL {
        try object.validate()
        if let cached = validCachedURL(for: object) {
            touch(object.id)
            return cached
        }
        if let task = inFlight[object.id] {
            return try await task.value
        }

        let task = Task<URL, Error> {
            try await self.downloadAndPromote(object)
        }
        inFlight[object.id] = task
        defer { inFlight[object.id] = nil }
        let url = try await task.value
        try enforceBudget(
            protectedID: protectedFromEviction ? object.id : nil
        )
        guard playableURL(for: object.id) != nil else {
            throw RemoteProviderError.serviceUnavailable(
                "The object exceeds the available cache budget."
            )
        }
        return url
    }

    func downloadAndPromote(
        _ object: RemoteMediaObject
    ) async throws -> URL {
        let stagedURL = stagingURL.appending(
            path: "\(UUID().uuidString).partial",
            directoryHint: .notDirectory
        )
        defer { try? fileManager.removeItem(at: stagedURL) }
        guard fileManager.createFile(
            atPath: stagedURL.path,
            contents: nil
        ) else {
            throw RemoteProviderError.serviceUnavailable(
                "The cache staging file could not be created."
            )
        }

        try await download(object, to: stagedURL)

        let relativePath = "Objects/\(object.sha256).\(object.fileExtension)"
        let destinationURL = rootURL.appending(
            path: relativePath,
            directoryHint: .notDirectory
        )
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.moveItem(at: stagedURL, to: destinationURL)
        }
        index[object.id] = RemoteCacheEntry(
            object: object,
            relativePath: relativePath,
            lastAccessedAt: Date()
        )
        try saveIndex()
        return destinationURL
    }

    func download(
        _ object: RemoteMediaObject,
        to stagedURL: URL
    ) async throws {
        let handle = try FileHandle(forWritingTo: stagedURL)
        do {
            let stream = try await provider.read(object: object.id, range: nil)
            var receivedBytes: Int64 = 0
            for try await chunk in stream {
                try Task.checkCancellation()
                receivedBytes += Int64(chunk.count)
                guard receivedBytes <= object.byteCount else {
                    throw RemoteProviderError.integrityMismatch
                }
                try handle.write(contentsOf: chunk)
            }
            try handle.close()
            guard receivedBytes == object.byteCount else {
                throw RemoteProviderError.interrupted
            }
        } catch {
            try? handle.close()
            throw error
        }
        guard try await ContentHasher().sha256(of: stagedURL) == object.sha256 else {
            throw RemoteProviderError.integrityMismatch
        }
    }

    func validCachedURL(
        for object: RemoteMediaObject
    ) -> URL? {
        guard let entry = index[object.id],
              entry.object == object
        else {
            removeEntry(for: object.id)
            return nil
        }
        let url = rootURL.appending(
            path: entry.relativePath,
            directoryHint: .notDirectory
        )
        guard let values = try? url.resourceValues(
            forKeys: [.fileSizeKey]
        ),
            Int64(values.fileSize ?? -1) == object.byteCount
        else {
            removeEntry(for: object.id)
            return nil
        }
        return url
    }

    func touch(
        _ id: RemoteObjectID
    ) {
        guard var entry = index[id] else {
            return
        }
        entry.lastAccessedAt = Date()
        index[id] = entry
        try? saveIndex()
    }

    func enforceBudget(
        protectedID: RemoteObjectID?
    ) throws {
        var total = index.entries.reduce(Int64(0)) {
            $0 + $1.object.byteCount
        }
        let candidates = index.entries
            .filter {
                !pinnedIDs.contains($0.object.id)
                    && $0.object.id != protectedID
            }
            .sorted {
                if $0.lastAccessedAt == $1.lastAccessedAt {
                    return $0.object.id.rawValue < $1.object.id.rawValue
                }
                return $0.lastAccessedAt < $1.lastAccessedAt
            }
        for entry in candidates where total > budgetBytes {
            removeEntry(for: entry.object.id)
            total -= entry.object.byteCount
        }
        try saveIndex()
    }

    func removeEntry(
        for id: RemoteObjectID
    ) {
        guard let entry = index[id] else {
            return
        }
        let sharedByAnotherEntry = index.entries.contains {
            $0.object.id != id && $0.relativePath == entry.relativePath
        }
        if !sharedByAnotherEntry {
            let url = rootURL.appending(
                path: entry.relativePath,
                directoryHint: .notDirectory
            )
            try? fileManager.removeItem(at: url)
        }
        index[id] = nil
    }

    func saveIndex() throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    func finishPrefetch(
        _ id: RemoteObjectID
    ) {
        prefetchTasks[id] = nil
    }

    static func loadIndex(
        from url: URL
    ) -> RemoteCacheIndex {
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(
                  RemoteCacheIndex.self,
                  from: data
              ),
              index.schemaVersion == RemoteCacheIndex.currentSchemaVersion
        else {
            return RemoteCacheIndex()
        }
        var sanitized = index
        sanitized.entries = index.entries.filter {
            validRelativePath($0.relativePath)
        }
        return sanitized
    }

    static func validRelativePath(
        _ path: String
    ) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.count == 2
            && components[0] == "Objects"
            && !components[1].isEmpty
            && components[1] != "."
            && components[1] != ".."
    }

    static func removeAbandonedStagingFiles(
        at url: URL,
        fileManager: FileManager
    ) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }
}
