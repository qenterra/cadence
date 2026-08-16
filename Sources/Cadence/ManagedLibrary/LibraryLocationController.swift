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
    let record: LibraryLocationRecord?
    let usesSecurityScope: Bool
}

enum LibraryLocationResolution: Equatable, Sendable {
    case available(ManagedLibraryLocation)
    case configurationUnavailable(String)
    case unavailable(previousParent: URL?)
    case staleBookmark(previousParent: URL)
    case identityMismatch(expected: LibraryIdentity, actual: LibraryIdentity)
}

/// Persists the bookmark and identity of an explicitly selected library.
///
/// A missing record means the standard Music location; corrupt records throw
/// so startup can present configuration recovery instead of silently resetting.
@MainActor
protocol LibraryLocationStoring: AnyObject {
    func load() throws -> LibraryLocationRecord?
    func save(_ record: LibraryLocationRecord?) throws
}

@MainActor
final class UserDefaultsLibraryLocationStore: LibraryLocationStoring {
    private static let key = "managedLibrary.location.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws -> LibraryLocationRecord? {
        guard let data = defaults.data(forKey: Self.key) else {
            return nil
        }
        return try JSONDecoder().decode(
            LibraryLocationRecord.self,
            from: data
        )
    }

    func save(_ record: LibraryLocationRecord?) throws {
        guard let record else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        let data = try JSONEncoder().encode(record)
        defaults.set(data, forKey: Self.key)
    }
}

struct ResolvedLibraryBookmark: Sendable {
    let parentURL: URL
    let isStale: Bool
}

/// Creates and resolves security-scoped bookmarks for a library parent folder.
///
/// The controller balances every successful `startAccessing` call with one
/// `stopAccessing` call when the location is replaced or released.
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
        let record: LibraryLocationRecord?
        do {
            record = try store.load()
        } catch {
            return .configurationUnavailable(
                "The saved library location settings are unreadable."
            )
        }
        guard let record else {
            return .available(fallback)
        }
        let resolved: ResolvedLibraryBookmark
        do {
            resolved = try bookmarkResolver.resolve(record.bookmarkData)
        } catch {
            return .unavailable(previousParent: nil)
        }
        guard bookmarkResolver.startAccessing(resolved.parentURL) else {
            return .unavailable(previousParent: resolved.parentURL)
        }

        let location = ManagedLibraryLocation(
            musicDirectory: resolved.parentURL
        )
        do {
            try location.migrateLegacyPackageIfNeeded()
        } catch {
            releaseAccess(to: resolved.parentURL)
            return .configurationUnavailable(error.localizedDescription)
        }
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
        if resolved.isStale {
            do {
                let bookmarkData = try bookmarkResolver.makeBookmark(
                    for: resolved.parentURL
                )
                try store.save(
                    LibraryLocationRecord(
                        bookmarkData: bookmarkData,
                        identity: record.identity
                    )
                )
            } catch {
                releaseAccess(to: resolved.parentURL)
                return .configurationUnavailable(
                    "The saved library permission could not be refreshed."
                )
            }
        }
        replaceAccessedParent(with: resolved.parentURL)
        return .available(location)
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
            ),
            usesSecurityScope: true
        )
    }

    /// Prepares a replacement without inventing a bookmark for the standard
    /// Music location. A missing persisted record is the canonical marker for
    /// that location; resets must preserve it.
    func prepareReplacementForCurrentLocation(
        parentURL: URL,
        identity: LibraryIdentity
    ) throws -> PreparedLibraryLocationActivation {
        guard try store.load() != nil else {
            return PreparedLibraryLocationActivation(
                parentURL: parentURL.standardizedFileURL,
                record: nil,
                usesSecurityScope: false
            )
        }
        return try prepareActivation(
            parentURL: parentURL,
            identity: identity
        )
    }

    func prepareReconnect(
        parentURL: URL
    ) throws -> PreparedLibraryLocationActivation {
        guard let expected = try store.load()?.identity else {
            throw ManagedLibraryError.musicDirectoryUnavailable
        }
        let location = ManagedLibraryLocation(musicDirectory: parentURL)
        try location.migrateLegacyPackageIfNeeded()
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
    ) throws {
        try store.save(activation.record)
        if activation.usesSecurityScope {
            replaceAccessedParent(with: activation.parentURL)
        } else if let accessedParentURL {
            bookmarkResolver.stopAccessing(accessedParentURL)
            self.accessedParentURL = nil
        }
        pendingParentURL = nil
    }

    func cancel(
        _ activation: PreparedLibraryLocationActivation
    ) {
        if activation.usesSecurityScope,
           pendingParentURL == activation.parentURL,
           accessedParentURL != activation.parentURL {
            bookmarkResolver.stopAccessing(activation.parentURL)
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
