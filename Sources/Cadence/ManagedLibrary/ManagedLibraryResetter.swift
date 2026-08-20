import Foundation

enum ManagedLibraryResetError: Error, LocalizedError, Sendable {
    case unavailable(URL)
    case invalidPackage(String)
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(url):
            "The managed library is unavailable at \(url.path)."
        case let .invalidPackage(message):
            "Cadence could not create a new empty library: \(message)"
        case let .rollbackFailed(message):
            "Cadence could not restore the original library: \(message)"
        }
    }
}

struct PreparedLibraryReset: Sendable {
    let location: ManagedLibraryLocation
    let identity: LibraryIdentity
    let originalIdentity: LibraryIdentity
    let backupURL: URL
}

actor ManagedLibraryResetter {
    typealias Validator = @Sendable (ManagedLibraryPackage) throws -> Void

    private let fileManager: FileManager
    private let validate: Validator

    init(
        fileManager: FileManager = .default,
        validate: @escaping Validator = { package in
            _ = try LibraryContainerFactory.persistentLocal(package: package)
        }
    ) {
        self.fileManager = fileManager
        self.validate = validate
    }

    func prepare(
        location: ManagedLibraryLocation
    ) throws -> PreparedLibraryReset {
        let (activePackage, originalIdentity) = try existingLibrary(at: location)

        let operationID = UUID()
        let stagingParent = location.musicDirectory.appending(
            path: ".Cadence-reset-\(operationID.uuidString)",
            directoryHint: .isDirectory
        )
        let backupURL = location.musicDirectory.appending(
            path: ".Cadence-library-backup-\(operationID.uuidString)",
            directoryHint: .isDirectory
        )
        let stagedLocation = ManagedLibraryLocation(musicDirectory: stagingParent)
        let stagedPackage = ManagedLibraryPackage(location: stagedLocation)
        let identity = LibraryIdentity()

        do {
            try stagedPackage.bootstrapForConfirmedImport(fileManager: fileManager)
            try stagedPackage.writeIdentity(identity, fileManager: fileManager)
            try validate(stagedPackage)

            try fileManager.moveItem(
                at: activePackage.packageURL,
                to: backupURL
            )
            do {
                try fileManager.moveItem(
                    at: stagedPackage.packageURL,
                    to: activePackage.packageURL
                )
                try validate(activePackage)
            } catch {
                try? fileManager.removeItem(at: activePackage.packageURL)
                try fileManager.moveItem(
                    at: backupURL,
                    to: activePackage.packageURL
                )
                throw error
            }

            try? fileManager.removeItem(at: stagingParent)
            return PreparedLibraryReset(
                location: location,
                identity: identity,
                originalIdentity: originalIdentity,
                backupURL: backupURL
            )
        } catch {
            cleanupFailedPreparation(at: stagingParent, identity: identity)
            throw ManagedLibraryResetError.invalidPackage(
                error.localizedDescription
            )
        }
    }

    func finish(_ prepared: PreparedLibraryReset) -> Bool {
        do {
            var trashedURL: NSURL?
            try fileManager.trashItem(
                at: prepared.backupURL,
                resultingItemURL: &trashedURL
            )
            removeLocalCatalog(for: prepared.originalIdentity)
            return true
        } catch {
            return false
        }
    }

    func rollback(_ prepared: PreparedLibraryReset) throws -> Bool {
        let activePackage = ManagedLibraryPackage(
            location: prepared.location
        )
        do {
            if fileManager.fileExists(atPath: activePackage.packageURL.path) {
                try fileManager.removeItem(at: activePackage.packageURL)
            }
            try fileManager.moveItem(
                at: prepared.backupURL,
                to: activePackage.packageURL
            )
            try validate(activePackage)
            removeLocalCatalog(for: prepared.identity)
            return true
        } catch {
            throw ManagedLibraryResetError.rollbackFailed(
                error.localizedDescription
            )
        }
    }

    private func removeLocalCatalog(
        for identity: LibraryIdentity
    ) {
        guard
            let localCatalog = try? LocalLibraryCatalogLocation.currentUser(
                identity: identity,
                fileManager: fileManager
            ),
            fileManager.fileExists(atPath: localCatalog.rootURL.path)
        else {
            return
        }
        try? fileManager.removeItem(at: localCatalog.rootURL)
    }

    private func existingLibrary(
        at location: ManagedLibraryLocation
    ) throws -> (ManagedLibraryPackage, LibraryIdentity) {
        let package = ManagedLibraryPackage(location: location)
        guard fileManager.fileExists(atPath: package.packageURL.path) else {
            throw ManagedLibraryResetError.unavailable(package.packageURL)
        }
        return try (package, package.readIdentity())
    }

    private func cleanupFailedPreparation(
        at stagingParent: URL,
        identity: LibraryIdentity
    ) {
        try? fileManager.removeItem(at: stagingParent)
        removeLocalCatalog(for: identity)
    }
}
