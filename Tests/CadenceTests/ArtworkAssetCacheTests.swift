@testable import Cadence
import Foundation
import Testing

@MainActor
struct ArtworkAssetCacheTests {
    @Test("Cache evicts the least recently used asset by byte cost")
    func evictsByCost() {
        let cache = ArtworkAssetCache(
            countLimit: 4,
            totalCostLimit: 8
        )
        let first = asset(byte: 1, count: 4)
        let second = asset(byte: 2, count: 4)
        let third = asset(byte: 3, count: 4)

        cache.insert(first)
        cache.insert(second)
        _ = cache.asset(id: first.id, revision: first.revision)
        cache.insert(third)

        #expect(cache.asset(id: first.id, revision: first.revision) != nil)
        #expect(cache.asset(id: second.id, revision: second.revision) == nil)
        #expect(cache.asset(id: third.id, revision: third.revision) != nil)
        #expect(cache.totalCost == 8)
    }

    @Test("A newer revision replaces only the matching artwork identity")
    func revisionsReplaceMatchingIdentity() {
        let cache = ArtworkAssetCache()
        let id = UUID()
        let previous = asset(id: id, revision: 1, byte: 1, count: 2)
        let current = asset(id: id, revision: 2, byte: 2, count: 3)
        let unrelated = asset(byte: 3, count: 4)

        cache.insert(previous)
        cache.insert(unrelated)
        cache.insert(current)

        #expect(cache.asset(id: id, revision: 1) == nil)
        #expect(cache.asset(id: id, revision: 2) == current)
        #expect(
            cache.asset(
                id: unrelated.id,
                revision: unrelated.revision
            ) == unrelated
        )
        #expect(cache.count == 2)
    }

    @Test("Assets larger than the byte budget are not retained")
    func rejectsOversizedAsset() {
        let cache = ArtworkAssetCache(
            countLimit: 4,
            totalCostLimit: 3
        )
        let oversized = asset(byte: 1, count: 4)

        cache.insert(oversized)

        #expect(cache.isEmpty)
        #expect(cache.totalCost == 0)
    }

    private func asset(
        id: UUID = UUID(),
        revision: Int = 0,
        byte: UInt8,
        count: Int
    ) -> ArtworkAsset {
        ArtworkAsset(
            id: id,
            revision: revision,
            data: Data(repeating: byte, count: count)
        )
    }
}
