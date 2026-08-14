import Foundation

@MainActor
final class ArtworkAssetCache {
    struct Key: Hashable, Sendable {
        let id: UUID
        let revision: Int
        let variant: ArtworkAssetVariant
    }

    private struct Entry {
        let asset: ArtworkAsset
        let cost: Int
    }

    let countLimit: Int
    let totalCostLimit: Int

    private var entries: [Key: Entry] = [:]
    private var recency: [Key] = []
    private(set) var totalCost = 0

    init(
        countLimit: Int = 128,
        totalCostLimit: Int = 64 * 1024 * 1024
    ) {
        self.countLimit = max(countLimit, 1)
        self.totalCostLimit = max(totalCostLimit, 1)
    }

    var count: Int {
        entries.count
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    func asset(
        id: UUID,
        revision: Int,
        variant: ArtworkAssetVariant = .thumbnail
    ) -> ArtworkAsset? {
        let key = Key(id: id, revision: revision, variant: variant)
        guard let entry = entries[key] else {
            return nil
        }
        touch(key)
        return entry.asset
    }

    func insert(
        _ asset: ArtworkAsset,
        variant: ArtworkAssetVariant = .thumbnail
    ) {
        let key = Key(
            id: asset.id,
            revision: asset.revision,
            variant: variant
        )
        invalidate(id: asset.id, exceptRevision: asset.revision)
        remove(key)

        let cost = asset.data.count
        guard cost <= totalCostLimit else {
            return
        }

        entries[key] = Entry(asset: asset, cost: cost)
        recency.append(key)
        totalCost += cost
        evictIfNeeded()
    }

    func invalidate(
        id: UUID,
        exceptRevision: Int? = nil
    ) {
        let keys = entries.keys.filter {
            $0.id == id && $0.revision != exceptRevision
        }
        for key in keys {
            remove(key)
        }
    }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func evictIfNeeded() {
        while entries.count > countLimit || totalCost > totalCostLimit {
            guard let leastRecent = recency.first else {
                break
            }
            remove(leastRecent)
        }
    }

    private func remove(_ key: Key) {
        guard let entry = entries.removeValue(forKey: key) else {
            return
        }
        recency.removeAll { $0 == key }
        totalCost -= entry.cost
    }
}
