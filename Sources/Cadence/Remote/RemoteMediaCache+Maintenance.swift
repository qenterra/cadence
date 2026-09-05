import Foundation

struct RemoteCacheClearResult: Equatable, Sendable {
    let removedObjectCount: Int
    let preservedObjectCount: Int
    let reclaimedBytes: Int64
}

extension RemoteMediaCache {
    func clear() throws -> RemoteCacheClearResult {
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()

        let protectedIDs = pinnedIDs.union(inFlight.keys)
        let removedEntries = index.entries.filter {
            !protectedIDs.contains($0.object.id)
        }
        guard !removedEntries.isEmpty else {
            return RemoteCacheClearResult(
                removedObjectCount: 0,
                preservedObjectCount: index.entries.count,
                reclaimedBytes: 0
            )
        }

        var updatedIndex = index
        for entry in removedEntries {
            updatedIndex[entry.object.id] = nil
        }
        try persist(updatedIndex)
        index = updatedIndex
        for entry in removedEntries {
            try removeObjectFileIfUnshared(entry)
        }
        return RemoteCacheClearResult(
            removedObjectCount: removedEntries.count,
            preservedObjectCount: index.entries.count,
            reclaimedBytes: removedEntries.reduce(0) {
                $0 + $1.object.byteCount
            }
        )
    }
}
