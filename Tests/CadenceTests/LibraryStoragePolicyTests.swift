@testable import Cadence
import Testing

struct LibraryStoragePolicyTests {
    @Test("Optimize storage permits eviction and hydrates only on demand")
    func optimizeStorage() {
        let policy = LibraryStoragePolicy(mode: .optimize)

        #expect(policy.permitsEviction)
        #expect(!policy.downloadsOriginalsEagerly)
    }

    @Test("Download Originals keeps the full music library on this Mac")
    func downloadOriginals() {
        let policy = LibraryStoragePolicy(mode: .downloadOriginals)

        #expect(!policy.permitsEviction)
        #expect(policy.downloadsOriginalsEagerly)
    }
}
