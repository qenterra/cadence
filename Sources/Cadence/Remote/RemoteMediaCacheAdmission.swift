import Foundation

struct RemoteCacheEvictionPlan {
    let index: RemoteCacheIndex
    let evictedEntries: [RemoteCacheEntry]

    static func make(
        index: RemoteCacheIndex,
        pinnedIDs: Set<RemoteObjectID>,
        protectedID: RemoteObjectID?,
        reservedBytes: Int64,
        budgetBytes: Int64
    ) throws -> Self {
        var total = index.entries.reduce(reservedBytes) {
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
        var updatedIndex = index
        var evictedEntries: [RemoteCacheEntry] = []
        for entry in candidates where total > budgetBytes {
            updatedIndex[entry.object.id] = nil
            evictedEntries.append(entry)
            total -= entry.object.byteCount
        }
        guard total <= budgetBytes else {
            throw RemoteProviderError.serviceUnavailable(
                "The object exceeds the available cache budget."
            )
        }
        return Self(index: updatedIndex, evictedEntries: evictedEntries)
    }
}

enum RemoteMediaCacheDownload {
    static func writeVerified(
        _ object: RemoteMediaObject,
        from provider: any RemoteLibraryProvider,
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
            // Preserve the download failure; startup reconciliation owns an
            // abandoned partial file if closing this handle also fails.
            try? handle.close()
            throw error
        }
        guard try await ContentHasher().sha256(of: stagedURL) == object.sha256 else {
            throw RemoteProviderError.integrityMismatch
        }
    }
}
