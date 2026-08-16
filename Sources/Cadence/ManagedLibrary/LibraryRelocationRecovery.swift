import Foundation

enum LibraryRelocationRecoveryError: Error, LocalizedError, Sendable {
    case manifestReadFailed(URL, String)
    case manifestDecodeFailed(URL, String)
    case manifestDirectoryReadFailed(URL, String)
    case unknownActiveLocation(UUID)
    case cleanupFailed(UUID, URL, String)

    var errorDescription: String? {
        switch self {
        case let .manifestReadFailed(url, message):
            "Cadence could not read the library-move record at \(url.path): \(message)"
        case let .manifestDecodeFailed(url, message):
            "Cadence could not decode the library-move record at \(url.path): \(message)"
        case let .manifestDirectoryReadFailed(url, message):
            "Cadence could not inspect library-move records at \(url.path): \(message)"
        case let .unknownActiveLocation(operationID):
            "Library move \(operationID.uuidString) does not include the active library location."
        case let .cleanupFailed(operationID, url, message):
            "Library move \(operationID.uuidString) could not clean up \(url.path): \(message)"
        }
    }
}

actor LibraryRelocationRecovery {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func recover(
        activeLocation: ManagedLibraryLocation
    ) throws {
        // Without an active library there is no authoritative side of a move.
        // Avoid probing its parent, which may be a sandbox redirect or offline
        // provider folder during a clean launch.
        guard fileManager.fileExists(
            atPath: activeLocation.packageURL.path
        ) else {
            return
        }
        let manifestURLs = try candidateManifestURLs(
            activeLocation: activeLocation
        )
        var manifests: [UUID: LibraryRelocationManifest] = [:]
        for url in manifestURLs {
            let manifest = try decodeManifest(at: url)
            manifests[manifest.operationID] = manifest
        }
        for manifest in manifests.values {
            try recover(manifest, activeLocation: activeLocation)
        }
    }

    private func decodeManifest(at url: URL) throws -> LibraryRelocationManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LibraryRelocationRecoveryError.manifestReadFailed(
                url,
                error.localizedDescription
            )
        }
        do {
            return try JSONDecoder().decode(
                LibraryRelocationManifest.self,
                from: data
            )
        } catch {
            throw LibraryRelocationRecoveryError.manifestDecodeFailed(
                url,
                error.localizedDescription
            )
        }
    }

    private func recover(
        _ manifest: LibraryRelocationManifest,
        activeLocation: ManagedLibraryLocation
    ) throws {
        let activePath = canonicalPath(activeLocation.packageURL)
        let sourceURL = migratedActiveURL(
            for: URL(filePath: manifest.sourcePackagePath),
            activeLocation: activeLocation
        )
        let destinationURL = migratedActiveURL(
            for: URL(filePath: manifest.destinationPackagePath),
            activeLocation: activeLocation
        )
        let sourcePath = canonicalPath(sourceURL)
        let destinationPath = canonicalPath(destinationURL)
        let destinationParent = destinationURL.deletingLastPathComponent()
        let stagingURL = destinationParent.appending(
            path: ".Cadence-relocation-\(manifest.operationID.uuidString)",
            directoryHint: .isDirectory
        )
        let parentManifestURL = destinationParent.appending(
            path: ".Cadence-relocation-\(manifest.operationID.uuidString).json"
        )
        let sourceManifestURL = sourceURL
            .appending(path: "Staging/Relocations", directoryHint: .isDirectory)
            .appending(path: "\(manifest.operationID.uuidString).json")
        let destinationManifestURL = destinationURL
            .appending(path: "Staging/Relocations", directoryHint: .isDirectory)
            .appending(path: "\(manifest.operationID.uuidString).json")

        if fileManager.fileExists(atPath: stagingURL.path) {
            try removeItem(
                at: stagingURL,
                operationID: manifest.operationID
            )
        }

        guard try cleanupInactivePackage(
            activePath: activePath,
            source: (url: sourceURL, path: sourcePath),
            destination: (url: destinationURL, path: destinationPath),
            operationID: manifest.operationID
        ) else {
            return
        }
        try removeItemIfPresent(
            at: parentManifestURL,
            operationID: manifest.operationID
        )
        try removeItemIfPresent(
            at: sourceManifestURL,
            operationID: manifest.operationID
        )
        try removeItemIfPresent(
            at: destinationManifestURL,
            operationID: manifest.operationID
        )
    }

    private func cleanupInactivePackage(
        activePath: String,
        source: (url: URL, path: String),
        destination: (url: URL, path: String),
        operationID: UUID
    ) throws -> Bool {
        guard let target = try cleanupTarget(
            activePath: activePath,
            source: source,
            destination: destination,
            operationID: operationID
        ) else {
            return true
        }
        do {
            try trash(target, operationID: operationID)
            return true
        } catch LibraryRelocationRecoveryError.cleanupFailed {
            // The selected library is already authoritative. Keep the journal
            // for a later retry instead of making that library unavailable.
            return false
        }
    }

    private func cleanupTarget(
        activePath: String,
        source: (url: URL, path: String),
        destination: (url: URL, path: String),
        operationID: UUID
    ) throws -> URL? {
        if activePath == destination.path {
            return fileManager.fileExists(atPath: source.url.path)
                ? source.url
                : nil
        }
        if activePath == source.path {
            return fileManager.fileExists(atPath: destination.url.path)
                ? destination.url
                : nil
        }
        throw LibraryRelocationRecoveryError.unknownActiveLocation(operationID)
    }

    private func trash(_ url: URL, operationID: UUID) throws {
        do {
            var trashedURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
        } catch {
            throw LibraryRelocationRecoveryError.cleanupFailed(
                operationID,
                url,
                error.localizedDescription
            )
        }
    }

    private func candidateManifestURLs(
        activeLocation: ManagedLibraryLocation
    ) throws -> [URL] {
        let package = ManagedLibraryPackage(location: activeLocation)
        let sourceDirectory = package.stagingDirectoryURL.appending(
            path: "Relocations",
            directoryHint: .isDirectory
        )
        return try contentsIfPresent(
            of: sourceDirectory
        )
    }

    private func contentsIfPresent(of directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        do {
            return try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw LibraryRelocationRecoveryError.manifestDirectoryReadFailed(
                directory,
                error.localizedDescription
            )
        }
    }

    private func removeItemIfPresent(
        at url: URL,
        operationID: UUID
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try removeItem(at: url, operationID: operationID)
    }

    private func removeItem(at url: URL, operationID: UUID) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw LibraryRelocationRecoveryError.cleanupFailed(
                operationID,
                url,
                error.localizedDescription
            )
        }
    }

    private func canonicalPath(
        _ url: URL
    ) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// A relocation interrupted before the folder-name migration still names
    /// `Cadence.library`. Only reinterpret that path when it is the legacy
    /// sibling of the active `Cadence` folder; unrelated move endpoints remain
    /// untouched.
    private func migratedActiveURL(
        for recordedURL: URL,
        activeLocation: ManagedLibraryLocation
    ) -> URL {
        guard
            recordedURL.lastPathComponent
            == ManagedLibraryLocation.legacyPackageFilename,
            canonicalPath(recordedURL.deletingLastPathComponent())
            == canonicalPath(activeLocation.musicDirectory)
        else {
            return recordedURL
        }
        return activeLocation.packageURL
    }
}
