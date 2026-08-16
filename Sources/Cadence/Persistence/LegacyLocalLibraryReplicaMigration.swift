import Foundation

struct LegacyLocalLibraryReplicaLocation: Equatable, Sendable {
    let rootURL: URL

    init(
        applicationSupportDirectory: URL,
        identity: LibraryIdentity
    ) {
        rootURL = applicationSupportDirectory
            .appending(path: "Cadence/Libraries", directoryHint: .isDirectory)
            .appending(path: identity.id.uuidString, directoryHint: .isDirectory)
    }

    var storeURL: URL {
        rootURL.appending(
            path: "Metadata/Library.store",
            directoryHint: .notDirectory
        )
    }
}

struct PreparedReplicaMigration: Sendable {
    let package: ManagedLibraryPackage
    let legacyRootURL: URL
    let backupDirectoryURL: URL
    let markerURL: URL
}

struct LegacyLocalLibraryReplicaMigration: Sendable {
    private static let sidecarSuffixes = ["", "-shm", "-wal"]
    private static let markerFilename = ".LegacyLocalReplicaMigrated"

    func prepareIfNeeded(
        package: ManagedLibraryPackage,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> PreparedReplicaMigration? {
        let identity = try package.readIdentity()
        let applicationSupportDirectory = try applicationSupportDirectory
            ?? currentApplicationSupportDirectory(fileManager: fileManager)
        let legacy = LegacyLocalLibraryReplicaLocation(
            applicationSupportDirectory: applicationSupportDirectory,
            identity: identity
        )
        let markerURL = package.metadataDirectoryURL.appending(
            path: Self.markerFilename,
            directoryHint: .notDirectory
        )
        guard
            fileManager.fileExists(atPath: legacy.storeURL.path),
            !fileManager.fileExists(atPath: markerURL.path)
        else {
            return nil
        }

        let backupDirectoryURL = package.stagingDirectoryURL.appending(
            path: "LegacyLocalReplicaBackup",
            directoryHint: .isDirectory
        )
        if fileManager.fileExists(atPath: backupDirectoryURL.path) {
            try fileManager.removeItem(at: backupDirectoryURL)
        }
        try fileManager.createDirectory(
            at: backupDirectoryURL,
            withIntermediateDirectories: true
        )
        let prepared = PreparedReplicaMigration(
            package: package,
            legacyRootURL: legacy.rootURL,
            backupDirectoryURL: backupDirectoryURL,
            markerURL: markerURL
        )
        do {
            try copyStore(
                from: package.metadataStoreURL,
                to: backupDirectoryURL.appending(path: "Library.store"),
                fileManager: fileManager
            )
            try replaceStore(
                at: package.metadataStoreURL,
                with: legacy.storeURL,
                fileManager: fileManager
            )
            return prepared
        } catch {
            try? rollback(prepared, fileManager: fileManager)
            throw error
        }
    }

    func commit(
        _ prepared: PreparedReplicaMigration,
        fileManager: FileManager = .default
    ) throws {
        try Data().write(to: prepared.markerURL, options: .atomic)
        try? fileManager.removeItem(at: prepared.legacyRootURL)
        try? fileManager.removeItem(at: prepared.backupDirectoryURL)
    }

    func rollback(
        _ prepared: PreparedReplicaMigration,
        fileManager: FileManager = .default
    ) throws {
        try replaceStore(
            at: prepared.package.metadataStoreURL,
            with: prepared.backupDirectoryURL.appending(path: "Library.store"),
            fileManager: fileManager
        )
        try? fileManager.removeItem(at: prepared.backupDirectoryURL)
    }
}

private extension LegacyLocalLibraryReplicaMigration {
    func currentApplicationSupportDirectory(
        fileManager: FileManager
    ) throws -> URL {
        guard let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ManagedLibraryError.musicDirectoryUnavailable
        }
        return directory
    }

    func replaceStore(
        at destinationURL: URL,
        with sourceURL: URL,
        fileManager: FileManager
    ) throws {
        for suffix in Self.sidecarSuffixes {
            let destination = URL(filePath: destinationURL.path + suffix)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
        }
        try copyStore(
            from: sourceURL,
            to: destinationURL,
            fileManager: fileManager
        )
    }

    func copyStore(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        for suffix in Self.sidecarSuffixes {
            let source = URL(filePath: sourceURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else {
                continue
            }
            let destination = URL(filePath: destinationURL.path + suffix)
            try fileManager.copyItem(at: source, to: destination)
        }
    }
}
