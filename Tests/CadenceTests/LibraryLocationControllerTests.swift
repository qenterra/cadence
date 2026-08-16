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

    @Test("Corrupt saved location settings fail explicitly")
    func corruptSettingsFailExplicitly() throws {
        let suiteName = "Cadence.LibraryLocation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            Data("not a location record".utf8),
            forKey: "managedLibrary.location.v1"
        )
        let controller = LibraryLocationController(
            store: UserDefaultsLibraryLocationStore(defaults: defaults),
            bookmarkResolver: BookmarkResolverStub()
        )
        let fallback = ManagedLibraryLocation(
            musicDirectory: URL(filePath: "/tmp/Cadence-Fallback")
        )

        guard case let .configurationUnavailable(message) =
            controller.resolveActiveLibrary(fallback: fallback) else {
            Issue.record("Expected an explicit settings failure.")
            return
        }
        #expect(message.contains("unreadable"))
    }

    @Test("A stale bookmark is refreshed without asking the user to locate the library")
    func staleBookmarkIsRefreshed() throws {
        let parent = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Stale-Bookmark-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let identity = LibraryIdentity(id: UUID(), formatVersion: 1)
        let location = ManagedLibraryLocation(musicDirectory: parent)
        try ManagedLibraryPackage(location: location).writeIdentity(identity)
        let store = InMemoryLibraryLocationStore(
            record: LibraryLocationRecord(
                bookmarkData: Data("stale-bookmark".utf8),
                identity: identity
            )
        )
        let resolver = BookmarkResolverStub(
            resolvedURL: parent,
            isStale: true,
            bookmarkData: Data("refreshed-bookmark".utf8)
        )
        let controller = LibraryLocationController(
            store: store,
            bookmarkResolver: resolver
        )

        #expect(
            controller.resolveActiveLibrary(
                fallback: location
            ) == .available(location)
        )
        #expect(try store.load()?.bookmarkData == Data("refreshed-bookmark".utf8))
        #expect(resolver.bookmarkCreationCount == 1)
        #expect(resolver.accessStartCount == 1)
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
        #expect(try store.load() == nil)

        try controller.commit(activation)
        #expect(try store.load()?.identity == identity)
    }

    @Test("Resetting the standard Music library does not create a bookmark")
    func standardLocationReplacement() throws {
        let parent = URL(filePath: "/Users/example/Music")
        let store = InMemoryLibraryLocationStore()
        let resolver = BookmarkResolverStub()
        let controller = LibraryLocationController(
            store: store,
            bookmarkResolver: resolver
        )

        let activation = try controller.prepareReplacementForCurrentLocation(
            parentURL: parent,
            identity: LibraryIdentity()
        )
        try controller.commit(activation)

        #expect(try store.load() == nil)
        #expect(resolver.bookmarkCreationCount == 0)
        #expect(resolver.accessStartCount == 0)
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

        #expect(try store.load() == original)
    }
}

@MainActor
private final class InMemoryLibraryLocationStore: LibraryLocationStoring {
    private var record: LibraryLocationRecord?

    init(record: LibraryLocationRecord? = nil) {
        self.record = record
    }

    func load() throws -> LibraryLocationRecord? {
        record
    }

    func save(_ record: LibraryLocationRecord?) throws {
        self.record = record
    }
}

@MainActor
private final class BookmarkResolverStub: LibraryBookmarkResolving {
    var resolvedURL = FileManager.default.temporaryDirectory.appending(
        path: "CadenceLibraryLocationControllerTests/ResolvedMusic",
        directoryHint: .isDirectory
    )
    var isStale = false
    var bookmarkData = Data("bookmark".utf8)
    var bookmarkCreationCount = 0
    var accessStartCount = 0

    init(
        resolvedURL: URL = FileManager.default.temporaryDirectory.appending(
            path: "CadenceLibraryLocationControllerTests/ResolvedMusic",
            directoryHint: .isDirectory
        ),
        isStale: Bool = false,
        bookmarkData: Data = Data("bookmark".utf8)
    ) {
        self.resolvedURL = resolvedURL
        self.isStale = isStale
        self.bookmarkData = bookmarkData
    }

    func makeBookmark(for _: URL) throws -> Data {
        bookmarkCreationCount += 1
        return bookmarkData
    }

    func resolve(_ data: Data) throws -> ResolvedLibraryBookmark {
        #expect(!data.isEmpty)
        return ResolvedLibraryBookmark(parentURL: resolvedURL, isStale: isStale)
    }

    func startAccessing(_: URL) -> Bool {
        accessStartCount += 1
        return true
    }

    func stopAccessing(_: URL) {}
}
