import CryptoKit
import Foundation

struct ContentHasher {
    static let defaultChunkSize = 1_048_576

    let chunkSize: Int

    init(chunkSize: Int = defaultChunkSize) {
        self.chunkSize = max(chunkSize, 4096)
    }

    func sha256(
        of url: URL
    ) async throws -> String {
        try Task.checkCancellation()

        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: chunkSize),
                  !data.isEmpty
            else {
                break
            }
            hasher.update(data: data)
        }

        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }

    func sha256(
        of data: Data
    ) -> String {
        SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }
}
