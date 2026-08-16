import Foundation

struct LocalLibraryReplicaLocation: Equatable, Sendable {
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
    ) throws -> LocalLibraryReplicaLocation {
        guard let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ManagedLibraryError.musicDirectoryUnavailable
        }
        return LocalLibraryReplicaLocation(
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
}

struct LocalLibraryReplicaSeeder: Sendable {
    private static let sidecarSuffixes = ["", "-shm", "-wal"]

    func seedIfNeeded(
        from sourceStoreURL: URL,
        to destinationStoreURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !fileManager.fileExists(atPath: destinationStoreURL.path) else {
            return
        }
        try fileManager.createDirectory(
            at: destinationStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard fileManager.fileExists(atPath: sourceStoreURL.path) else {
            return
        }
        for suffix in Self.sidecarSuffixes {
            let source = URL(filePath: sourceStoreURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else {
                continue
            }
            let destination = URL(filePath: destinationStoreURL.path + suffix)
            try fileManager.copyItem(at: source, to: destination)
        }
    }
}
