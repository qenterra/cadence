@testable import Cadence
import Foundation
import Testing

struct LocalLibraryReplicaTests {
    @Test("Each logical library has one stable Application Support replica")
    func stableReplicaLocation() {
        let root = URL(filePath: "/tmp/Cadence Application Support")
        let identity = LibraryIdentity(
            id: UUID(
                uuid: (
                    0x11, 0x11, 0x11, 0x11,
                    0x22, 0x22,
                    0x33, 0x33,
                    0x44, 0x44,
                    0x55, 0x55, 0x55, 0x55, 0x55, 0x55
                )
            ),
            formatVersion: 1
        )

        let location = LocalLibraryReplicaLocation(
            applicationSupportDirectory: root,
            identity: identity
        )

        #expect(
            location.storeURL.path
                == "/tmp/Cadence Application Support/Cadence/Libraries/"
                + "11111111-2222-3333-4444-555555555555/Metadata/Library.store"
        )
    }

    @Test("The local replica is seeded once from the legacy package store")
    func seedLegacyStore() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Replica-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Legacy.store")
        let replica = root.appending(path: "Replica/Library.store")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("legacy".utf8).write(to: source)

        try LocalLibraryReplicaSeeder().seedIfNeeded(
            from: source,
            to: replica
        )
        try Data("local-change".utf8).write(to: replica)
        try LocalLibraryReplicaSeeder().seedIfNeeded(
            from: source,
            to: replica
        )

        #expect(try Data(contentsOf: replica) == Data("local-change".utf8))
    }
}
