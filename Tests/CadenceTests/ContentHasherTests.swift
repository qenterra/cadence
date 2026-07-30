@testable import Cadence
import Foundation
import Testing

struct ContentHasherTests {
    @Test("SHA-256 is streamed and returned as lowercase hexadecimal")
    func knownDigest() async throws {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "CadenceHasher-\(UUID().uuidString)"
        )
        try Data("abc".utf8).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let digest = try await ContentHasher().sha256(of: url)

        #expect(
            digest
                == "ba7816bf8f01cfea414140de5dae2223"
                + "b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("Cancellation is observed before file access")
    func cancellation() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ContentHasher().sha256(
                of: URL(filePath: "/does/not/exist")
            )
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
