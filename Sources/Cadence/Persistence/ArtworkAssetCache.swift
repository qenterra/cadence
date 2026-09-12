import Foundation
import QenTerraFoundation

@MainActor
final class ArtworkAssetCache {
    struct Key: Hashable, Sendable {
        let id: UUID
        let revision: Int
        let variant: ArtworkAssetVariant
    }

    private var cache: CostLimitedCache<Key, ArtworkAsset>

    init(countLimit: Int = 128, totalCostLimit: Int = 64 * 1024 * 1024) {
        cache = CostLimitedCache(countLimit: countLimit, totalCostLimit: totalCostLimit)
    }

    var totalCost: Int {
        cache.totalCost
    }

    var count: Int {
        cache.count
    }

    var isEmpty: Bool {
        cache.isEmpty
    }

    func asset(id: UUID, revision: Int, variant: ArtworkAssetVariant = .thumbnail) -> ArtworkAsset? {
        cache.value(forKey: Key(id: id, revision: revision, variant: variant))
    }

    func insert(_ asset: ArtworkAsset, variant: ArtworkAssetVariant = .thumbnail) {
        invalidate(id: asset.id, exceptRevision: asset.revision)
        cache.insert(
            asset,
            forKey: Key(id: asset.id, revision: asset.revision, variant: variant),
            cost: asset.data.count
        )
    }

    func invalidate(id: UUID, exceptRevision: Int? = nil) {
        cache.removeAll { $0.id == id && $0.revision != exceptRevision }
    }
}
