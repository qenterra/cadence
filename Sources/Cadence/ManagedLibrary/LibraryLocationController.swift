import Foundation

struct LibraryIdentity: Codable, Equatable, Hashable, Sendable {
    static let currentFormatVersion = 1

    let id: UUID
    let formatVersion: Int

    init(
        id: UUID = UUID(),
        formatVersion: Int = currentFormatVersion
    ) {
        self.id = id
        self.formatVersion = formatVersion
    }
}

struct LibraryLocationRecord: Codable, Equatable, Sendable {
    let bookmarkData: Data
    let identity: LibraryIdentity
}

struct PreparedLibraryLocationActivation: Sendable {
    let parentURL: URL
    let record: LibraryLocationRecord
}

enum LibraryLocationResolution: Equatable, Sendable {
    case available(ManagedLibraryLocation)
    case unavailable(previousParent: URL?)
    case staleBookmark(previousParent: URL)
    case identityMismatch(expected: LibraryIdentity, actual: LibraryIdentity)
}

@MainActor
protocol LibraryLocationStoring: AnyObject {
    var record: LibraryLocationRecord? { get set }
}

@MainActor
final class UserDefaultsLibraryLocationStore: LibraryLocationStoring {
    private static let key = "managedLibrary.location.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var record: LibraryLocationRecord? {
        get {
            guard let data = defaults.data(forKey: Self.key) else {
                return nil
            }
            return try? JSONDecoder().decode(
                LibraryLocationRecord.self,
                from: data
            )
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue)
            else {
                defaults.removeObject(forKey: Self.key)
                return
            }
            defaults.set(data, forKey: Self.key)
        }
    }
}

struct ResolvedLibraryBookmark: Sendable {
    let parentURL: URL
    let isStale: Bool
}

@MainActor
protocol LibraryBookmarkResolving {
    func makeBookmark(for parentURL: URL) throws -> Data
    func resolve(_ data: Data) throws -> ResolvedLibraryBookmark
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

@MainActor
struct SecurityScopedLibraryBookmarkResolver: LibraryBookmarkResolving {
    func makeBookmark(for parentURL: URL) throws -> Data {
        try parentURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolve(_ data: Data) throws -> ResolvedLibraryBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedLibraryBookmark(
            parentURL: url.standardizedFileURL,
            isStale: isStale
        )
    }

    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

@MainActor
final class LibraryLocationController {
    private let store: any LibraryLocationStoring
    private let bookmarkResolver: any LibraryBookmarkResolving
    private var accessedParentURL: URL?
    private var pendingParentURL: URL?

    init(
        store: any LibraryLocationStoring = UserDefaultsLibraryLocationStore(),
        bookmarkResolver: any LibraryBookmarkResolving = SecurityScopedLibraryBookmarkResolver()
    ) {
        self.store = store
        self.bookmarkResolver = bookmarkResolver
    }

    func resolveActiveLibrary(
        fallback: ManagedLibraryLocation
    ) -> LibraryLocationResolution {
        guard let record = store.record else {
            return .available(fallback)
        }
        let resolved: ResolvedLibraryBookmark
        do {
            resolved = try bookmarkResolver.resolve(record.bookmarkData)
        } catch {
            return .unavailable(previousParent: nil)
        }
        guard !resolved.isStale else {
            return .staleBookmark(previousParent: resolved.parentURL)
        }
        guard bookmarkResolver.startAccessing(resolved.parentURL) else {
            return .unavailable(previousParent: resolved.parentURL)
        }
        replaceAccessedParent(with: resolved.parentURL)

        let location = ManagedLibraryLocation(
            musicDirectory: resolved.parentURL
        )
        guard let actualIdentity = try? ManagedLibraryPackage(
            location: location
        ).readIdentity() else {
            releaseAccess(to: resolved.parentURL)
            return .unavailable(previousParent: resolved.parentURL)
        }
        guard actualIdentity == record.identity else {
            releaseAccess(to: resolved.parentURL)
            return .identityMismatch(
                expected: record.identity,
                actual: actualIdentity
            )
        }
        return .available(location)
    }

    func activate(
        parentURL: URL,
        identity: LibraryIdentity
    ) throws {
        let activation = try prepareActivation(
            parentURL: parentURL,
            identity: identity
        )
        commit(activation)
    }

    func prepareActivation(
        parentURL: URL,
        identity: LibraryIdentity
    ) throws -> PreparedLibraryLocationActivation {
        let parentURL = parentURL.standardizedFileURL
        let bookmark = try bookmarkResolver.makeBookmark(for: parentURL)
        guard bookmarkResolver.startAccessing(parentURL) else {
            throw ManagedLibraryError.musicDirectoryUnavailable
        }
        if let pendingParentURL,
           pendingParentURL != parentURL {
            bookmarkResolver.stopAccessing(pendingParentURL)
        }
        pendingParentURL = parentURL
        return PreparedLibraryLocationActivation(
            parentURL: parentURL,
            record: LibraryLocationRecord(
                bookmarkData: bookmark,
                identity: identity
            )
        )
    }

    func prepareReconnect(
        parentURL: URL
    ) throws -> PreparedLibraryLocationActivation {
        guard let expected = store.record?.identity else {
            throw ManagedLibraryError.musicDirectoryUnavailable
        }
        let location = ManagedLibraryLocation(musicDirectory: parentURL)
        let actual = try ManagedLibraryPackage(location: location).readIdentity()
        guard actual == expected else {
            throw LibraryRelocationError.invalidDestination(
                "This folder contains a different Cadence library."
            )
        }
        return try prepareActivation(
            parentURL: parentURL,
            identity: expected
        )
    }

    func commit(
        _ activation: PreparedLibraryLocationActivation
    ) {
        store.record = activation.record
        replaceAccessedParent(with: activation.parentURL)
        pendingParentURL = nil
    }

    func cancel(
        _ activation: PreparedLibraryLocationActivation
    ) {
        if pendingParentURL == activation.parentURL,
           accessedParentURL != activation.parentURL {
            bookmarkResolver.stopAccessing(activation.parentURL)
        }
        pendingParentURL = nil
    }

    func clearCustomLocation() {
        store.record = nil
        if let accessedParentURL {
            bookmarkResolver.stopAccessing(accessedParentURL)
            self.accessedParentURL = nil
        }
        if let pendingParentURL,
           pendingParentURL != accessedParentURL {
            bookmarkResolver.stopAccessing(pendingParentURL)
        }
        pendingParentURL = nil
    }

    private func replaceAccessedParent(
        with parentURL: URL
    ) {
        if let accessedParentURL,
           accessedParentURL != parentURL {
            bookmarkResolver.stopAccessing(accessedParentURL)
        }
        accessedParentURL = parentURL
    }

    private func releaseAccess(
        to parentURL: URL
    ) {
        bookmarkResolver.stopAccessing(parentURL)
        if accessedParentURL == parentURL {
            accessedParentURL = nil
        }
    }
}
