@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibraryLocationControllerTests {
    @Test("No bookmark keeps the current Music location")
    func defaultLocation() {
        let fallback = ManagedLibraryLocation(
            musicDirectory: FileManager.default.temporaryDirectory.appending(
                path: "CadenceLibraryLocationControllerTests/Music",
                directoryHint: .isDirectory
            )
        )
        let controller = LibraryLocationController(
            store: InMemoryLibraryLocationStore(),
            bookmarkResolver: BookmarkResolverStub()
        )

        #expect(controller.resolveActiveLibrary(fallback: fallback) == .available(fallback))
    }

    @Test("A stale bookmark fails closed and asks the user to locate the library")
    func staleBookmark() {
        let parent = URL(filePath: "/Volumes/Music")
        let identity = LibraryIdentity(id: UUID(), formatVersion: 1)
        let store = InMemoryLibraryLocationStore(
            record: LibraryLocationRecord(
                bookmarkData: Data("bookmark".utf8),
                identity: identity
            )
        )
        let controller = LibraryLocationController(
            store: store,
            bookmarkResolver: BookmarkResolverStub(
                resolvedURL: parent,
                isStale: true
            )
        )

        #expect(
            controller.resolveActiveLibrary(
                fallback: ManagedLibraryLocation(musicDirectory: parent)
            ) == .staleBookmark(previousParent: parent)
        )
    }

    @Test("A different package identity is never opened silently")
    func identityMismatch() throws {
        let parent = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Identity-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let expected = LibraryIdentity(id: UUID(), formatVersion: 1)
        let actual = LibraryIdentity(id: UUID(), formatVersion: 1)
        let location = ManagedLibraryLocation(musicDirectory: parent)
        try ManagedLibraryPackage(location: location).writeIdentity(actual)

        let controller = LibraryLocationController(
            store: InMemoryLibraryLocationStore(
                record: LibraryLocationRecord(
                    bookmarkData: Data("bookmark".utf8),
                    identity: expected
                )
            ),
            bookmarkResolver: BookmarkResolverStub(resolvedURL: parent)
        )

        #expect(
            controller.resolveActiveLibrary(fallback: location)
                == .identityMismatch(expected: expected, actual: actual)
        )
    }

    @Test("Prepared activation is persisted only after commit")
    func activationCommit() throws {
        let parent = URL(filePath: "/Volumes/Portable Music")
        let identity = LibraryIdentity(id: UUID(), formatVersion: 1)
        let store = InMemoryLibraryLocationStore()
        let controller = LibraryLocationController(
            store: store,
            bookmarkResolver: BookmarkResolverStub()
        )

        let activation = try controller.prepareActivation(
            parentURL: parent,
            identity: identity
        )
        #expect(store.record == nil)

        controller.commit(activation)
        #expect(store.record?.identity == identity)
    }

    @Test("Cancelling a prepared activation preserves the current location")
    func activationCancellation() throws {
        let original = LibraryLocationRecord(
            bookmarkData: Data("original".utf8),
            identity: LibraryIdentity(id: UUID(), formatVersion: 1)
        )
        let store = InMemoryLibraryLocationStore(record: original)
        let controller = LibraryLocationController(
            store: store,
            bookmarkResolver: BookmarkResolverStub()
        )

        let activation = try controller.prepareActivation(
            parentURL: URL(filePath: "/Volumes/Cancelled"),
            identity: LibraryIdentity(id: UUID(), formatVersion: 1)
        )
        controller.cancel(activation)

        #expect(store.record == original)
    }
}

@MainActor
private final class InMemoryLibraryLocationStore: LibraryLocationStoring {
    var record: LibraryLocationRecord?

    init(record: LibraryLocationRecord? = nil) {
        self.record = record
    }
}

@MainActor
private struct BookmarkResolverStub: LibraryBookmarkResolving {
    var resolvedURL = FileManager.default.temporaryDirectory.appending(
        path: "CadenceLibraryLocationControllerTests/ResolvedMusic",
        directoryHint: .isDirectory
    )
    var isStale = false

    func makeBookmark(for _: URL) throws -> Data {
        Data("bookmark".utf8)
    }

    func resolve(_ data: Data) throws -> ResolvedLibraryBookmark {
        #expect(!data.isEmpty)
        return ResolvedLibraryBookmark(parentURL: resolvedURL, isStale: isStale)
    }

    func startAccessing(_: URL) -> Bool {
        true
    }

    func stopAccessing(_: URL) {}
}
