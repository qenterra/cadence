@testable import Cadence
import Foundation
import Testing

enum ArtworkLookupTestError: Error {
    case staleMetadata
}

struct LibraryStoreArtworkLookupCapacityTests {
    @Test("Artwork metadata results retain a bounded FIFO order")
    func artworkMetadataResultCacheMaintainsBoundedFIFO() {
        let epoch: UInt64 = 7
        let ids = (0 ..< 258).map(artworkID)
        let entry = ArtworkMetadataResultEntry(epoch: epoch, artwork: nil)
        var cache = ArtworkMetadataResultCache()

        for id in ids.prefix(256) {
            cache.insert(entry, id: id)
        }
        let initialOrder = Array(ids.prefix(256))
        #expect(cache.count == 256)
        #expect(cache.result(id: ids[0], epoch: epoch) != nil)
        #expect(cache.result(id: ids[0], epoch: epoch)?.artwork == nil)
        #expect(cache.insertionOrderedIDs == initialOrder)

        cache.insert(entry, id: ids[5])
        #expect(cache.count == 256)
        #expect(cache.insertionOrderedIDs == initialOrder)

        cache.insert(entry, id: ids[256])
        #expect(cache.count == 256)
        #expect(cache.result(id: ids[0], epoch: epoch) == nil)
        #expect(cache.insertionOrderedIDs == Array(ids[1 ... 256]))

        cache.invalidate(id: ids[1])
        cache.insert(entry, id: ids[1])
        cache.insert(entry, id: ids[257])
        #expect(cache.count == 256)
        #expect(cache.result(id: ids[2], epoch: epoch) == nil)
        #expect(
            cache.insertionOrderedIDs
                == Array(ids[3 ... 256]) + [ids[1], ids[257]]
        )
    }

    private func artworkID(_ index: Int) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0,
                0, 0, 0, 0,
                0, 0, 0, 0,
                0, 0,
                UInt8((index >> 8) & 0xFF),
                UInt8(index & 0xFF)
            )
        )
    }
}

final class GatedArtworkDataProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private let releaseGate = DispatchSemaphore(value: 0)
    private let data: Data
    private var count = 0
    private var cancellation: Bool?

    init(data: Data) {
        self.data = data
    }

    var loader: ArtworkDataLoader {
        ArtworkDataLoader { [self] _ in
            locked {
                count += 1
            }
            started.signal()
            releaseGate.wait()
            locked {
                cancellation = withUnsafeCurrentTask {
                    $0?.isCancelled ?? false
                }
            }
            return data
        }
    }

    var invocationCount: Int {
        locked { count }
    }

    var observedCancellation: Bool? {
        locked { cancellation }
    }

    func waitUntilStarted() async {
        await Task.detached { [self] in
            waitSynchronouslyUntilStarted()
        }.value
    }

    func release() {
        releaseGate.signal()
    }

    private func waitSynchronouslyUntilStarted() {
        started.wait()
    }

    private func locked<Value>(_ operation: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

final class CountingArtworkDataProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let data: Data
    private var count = 0

    init(data: Data) {
        self.data = data
    }

    var loader: ArtworkDataLoader {
        ArtworkDataLoader { [self] _ in
            locked {
                count += 1
            }
            return data
        }
    }

    var invocationCount: Int {
        locked { count }
    }

    private func locked<Value>(_ operation: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
