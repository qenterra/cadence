import Foundation

struct LocalLibraryCatalogLocation: Equatable, Sendable {
    let rootURL: URL

    init(
        applicationSupportDirectory: URL,
        identity: LibraryIdentity
    ) {
        rootURL = applicationSupportDirectory
            .appending(path: "Cadence/Libraries", directoryHint: .isDirectory)
            .appending(path: identity.id.uuidString, directoryHint: .isDirectory)
    }

    static func currentUser(
        identity: LibraryIdentity,
        fileManager: FileManager = .default
    ) throws -> LocalLibraryCatalogLocation {
        guard let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ManagedLibraryError.musicDirectoryUnavailable
        }
        return LocalLibraryCatalogLocation(
            applicationSupportDirectory: applicationSupportDirectory,
            identity: identity
        )
    }

    var metadataDirectoryURL: URL {
        rootURL.appending(path: "Metadata", directoryHint: .isDirectory)
    }

    var storeURL: URL {
        metadataDirectoryURL.appending(
            path: "Library.store",
            directoryHint: .notDirectory
        )
    }

    var lyricsSearchDatabaseURL: URL {
        metadataDirectoryURL.appending(
            path: "Search.sqlite",
            directoryHint: .notDirectory
        )
    }
}

struct PreparedLocalLibraryCatalogMigration: Sendable {
    let package: ManagedLibraryPackage
    let localCatalog: LocalLibraryCatalogLocation
}

struct LocalLibraryCatalogMigration: Sendable {
    private static let sidecarSuffixes = ["", "-shm", "-wal"]

    func prepareIfNeeded(
        package: ManagedLibraryPackage,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> PreparedLocalLibraryCatalogMigration? {
        let identity = try package.readIdentity()
        let localCatalog = if let applicationSupportDirectory {
            LocalLibraryCatalogLocation(
                applicationSupportDirectory: applicationSupportDirectory,
                identity: identity
            )
        } else {
            try LocalLibraryCatalogLocation.currentUser(
                identity: identity,
                fileManager: fileManager
            )
        }
        guard !fileManager.fileExists(atPath: localCatalog.storeURL.path) else {
            return nil
        }
        guard fileManager.fileExists(atPath: package.metadataStoreURL.path) else {
            return nil
        }

        try copyStore(
            from: package.metadataStoreURL,
            to: localCatalog.storeURL,
            fileManager: fileManager
        )
        return PreparedLocalLibraryCatalogMigration(
            package: package,
            localCatalog: localCatalog
        )
    }

    func commit(
        _ prepared: PreparedLocalLibraryCatalogMigration,
        fileManager: FileManager = .default
    ) throws {
        removeFiles(rootedAt: prepared.package.metadataStoreURL, fileManager: fileManager)
        removeFiles(
            rootedAt: prepared.package.lyricsSearchDatabaseURL,
            fileManager: fileManager
        )
    }

    func rollback(
        _ prepared: PreparedLocalLibraryCatalogMigration,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: prepared.localCatalog.rootURL.path) {
            try fileManager.removeItem(at: prepared.localCatalog.rootURL)
        }
    }
}

private extension LocalLibraryCatalogMigration {
    func copyStore(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            for suffix in Self.sidecarSuffixes {
                let source = URL(filePath: sourceURL.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else {
                    continue
                }
                let destination = URL(filePath: destinationURL.path + suffix)
                try fileManager.copyItem(at: source, to: destination)
            }
        } catch {
            try? fileManager.removeItem(
                at: destinationURL.deletingLastPathComponent()
            )
            throw error
        }
    }

    func removeFiles(
        rootedAt rootURL: URL,
        fileManager: FileManager
    ) {
        for suffix in Self.sidecarSuffixes {
            let url = URL(filePath: rootURL.path + suffix)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }
            try? fileManager.removeItem(at: url)
        }
    }
}
