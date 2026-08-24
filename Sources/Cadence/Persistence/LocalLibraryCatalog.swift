import CryptoKit
import Darwin
import Foundation
import GRDB

// The versioned manifest and its recovery state machine intentionally remain
// colocated so schema and transition edits cannot drift across files.
// swiftlint:disable file_length

struct LocalLibraryCatalogLocation: Equatable, Sendable {
    let applicationSupportDirectoryURL: URL
    let rootURL: URL

    init(
        applicationSupportDirectory: URL,
        identity: LibraryIdentity
    ) {
        applicationSupportDirectoryURL = applicationSupportDirectory.standardizedFileURL
        rootURL = applicationSupportDirectoryURL
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

    var migrationManifestURL: URL {
        rootURL.appending(
            path: "CatalogMigration.json",
            directoryHint: .notDirectory
        )
    }

    var transactionLockURL: URL {
        rootURL.appending(
            path: "CatalogTransaction.lock",
            directoryHint: .notDirectory
        )
    }
}

struct LocalCatalogPathGuard: Sendable {
    private let trustedRoot: URL

    init(trustedRoot: URL) {
        self.trustedRoot = trustedRoot.standardizedFileURL
    }

    func ensureDirectoryChain(
        to directory: URL,
        fileManager: FileManager
    ) throws {
        try ensureTrustedRoot(fileManager: fileManager)
        var current = trustedRoot
        for component in try relativeComponents(to: directory) {
            let next = current.appending(
                path: component,
                directoryHint: .isDirectory
            )
            if try entryStatus(at: next) == .missing {
                try fileManager.createDirectory(
                    at: next,
                    withIntermediateDirectories: false
                )
            } else {
                try requireDirectory(next)
            }
            current = next
        }
    }

    func validateDirectoryChain(to directory: URL) throws {
        try requireDirectory(trustedRoot)
        var current = trustedRoot
        for component in try relativeComponents(to: directory) {
            current.append(path: component, directoryHint: .isDirectory)
            try requireDirectory(current)
        }
    }

    func regularFileExists(at file: URL) throws -> Bool {
        try validateDirectoryChain(to: file.deletingLastPathComponent())
        switch try entryStatus(at: file) {
        case .missing:
            return false
        case .regular:
            return true
        case .directory, .other:
            throw LocalCatalogMigrationError.unsafePath(file.path)
        }
    }

    func directoryExists(at directory: URL) throws -> Bool {
        try validateDirectoryChain(to: directory.deletingLastPathComponent())
        switch try entryStatus(at: directory) {
        case .missing:
            return false
        case .directory:
            return true
        case .regular, .other:
            throw LocalCatalogMigrationError.unsafePath(directory.path)
        }
    }

    private enum EntryStatus: Equatable {
        case missing
        case regular
        case directory
        case other
    }

    private func ensureTrustedRoot(fileManager: FileManager) throws {
        switch try entryStatus(at: trustedRoot) {
        case .missing:
            try requireDirectory(trustedRoot.deletingLastPathComponent())
            try fileManager.createDirectory(
                at: trustedRoot,
                withIntermediateDirectories: false
            )
        case .directory:
            break
        case .regular, .other:
            throw LocalCatalogMigrationError.unsafePath(trustedRoot.path)
        }
    }

    private func relativeComponents(to candidate: URL) throws -> [String] {
        let rootComponents = trustedRoot.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        guard candidateComponents.starts(with: rootComponents) else {
            throw LocalCatalogMigrationError.unsafePath(candidate.path)
        }
        return Array(candidateComponents.dropFirst(rootComponents.count))
    }

    private func requireDirectory(_ url: URL) throws {
        guard try entryStatus(at: url) == .directory else {
            throw LocalCatalogMigrationError.unsafePath(url.path)
        }
    }

    private func entryStatus(at url: URL) throws -> EntryStatus {
        var information = stat()
        guard Darwin.lstat(url.path, &information) == 0 else {
            if errno == ENOENT {
                return .missing
            }
            throw LocalCatalogMigrationError.unsafePath(url.path)
        }
        let kind = information.st_mode & S_IFMT
        if kind == S_IFREG {
            return .regular
        }
        if kind == S_IFDIR {
            return .directory
        }
        return .other
    }
}

func readLocalCatalogIdentity(
    package: ManagedLibraryPackage,
    fileManager _: FileManager
) throws -> LibraryIdentity {
    let guardRoot = LocalCatalogPathGuard(
        trustedRoot: package.location.musicDirectory
    )
    guard try guardRoot.regularFileExists(at: package.identityURL) else {
        throw LocalCatalogMigrationError.unsafePath(package.identityURL.path)
    }
    return try JSONDecoder().decode(
        LibraryIdentity.self,
        from: Data(contentsOf: package.identityURL)
    )
}

struct PreparedLocalLibraryCatalogMigration: Sendable {
    let package: ManagedLibraryPackage
    let localCatalog: LocalLibraryCatalogLocation
    let operationID: UUID
    let libraryID: UUID
}

struct LocalCatalogPointer: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let libraryID: UUID
}

struct LocalCatalogMigrationManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let operationID: UUID
    let libraryID: UUID
    let origin: Origin
    let sourceStoreRelativePath: String?
    let stagingDirectoryName: String
    let legacyDirectoryName: String?
    var phase: Phase
    var sourceFiles: [SourceFile]
    var stagedSnapshot: Snapshot?

    enum Origin: String, Codable, Equatable, Sendable {
        case packageSnapshot
        case adoptedValidatedLocal
    }

    enum Phase: String, Codable, Equatable, Sendable {
        case prepared
        case mainCopied
        case walHandled
        case shmDispositionRecorded
        case validating
        case validated
        case promoting
        case promoted
        case rollingBack
        case sourceCleanup
        case complete
    }

    struct SourceFile: Codable, Equatable, Sendable {
        enum Role: String, Codable, Equatable, Sendable {
            case main
            case wal
            case shm
        }

        enum Disposition: String, Codable, Equatable, Sendable {
            case copied
            case absent
            case rebuild
        }

        let role: Role
        let disposition: Disposition
        let byteCount: Int64?
        let sha256: String?
    }

    struct Snapshot: Codable, Equatable, Sendable {
        let byteCount: Int64
        let sha256: String
        let quickCheck: String
    }
}

enum LocalCatalogMigrationFailurePoint: String, CaseIterable, Sendable {
    case afterLegacyMoveIntent
    case afterLegacyMoveRename
    case afterPrepared
    case afterMainCopied
    case afterWALHandled
    case afterSHMDispositionRecorded
    case afterValidated
    case afterPromotionIntent
    case afterPromotionRename
    case afterPromoted
    case afterRollbackIntent
    case afterRollbackFinalRemoval
    case afterRollbackStageRemoval
    case beforeRollbackPrepared
    case afterRollbackPrepared
    case afterSourceCleanupIntent
    case afterSourceMainRemoved
    case afterSourceWALRemoved
    case afterSourceSHMRemoved
    case afterSearchMainRemoved
    case afterSearchWALRemoved
    case afterSearchSHMRemoved
}

struct LocalCatalogMigrationFaultInjector: Sendable {
    static let disabled = LocalCatalogMigrationFaultInjector { _ in }

    private let handler: @Sendable (LocalCatalogMigrationFailurePoint) throws -> Void

    init(
        _ handler: @escaping @Sendable (
            LocalCatalogMigrationFailurePoint
        ) throws -> Void
    ) {
        self.handler = handler
    }

    func inject(_ point: LocalCatalogMigrationFailurePoint) throws {
        try handler(point)
    }
}

struct LocalCatalogDurability: Sendable {
    static let live = LocalCatalogDurability(
        syncFile: syncFileLive,
        syncDirectory: syncDirectoryLive,
        atomicRename: atomicRenameLive
    )

    let syncFile: @Sendable (URL) throws -> Void
    let syncDirectory: @Sendable (URL) throws -> Void
    let atomicRename: @Sendable (URL, URL) throws -> Void
}

enum LocalCatalogMigrationError: Error, Equatable, LocalizedError, Sendable {
    case corruptManifest(String)
    case unsupportedManifestSchema(Int)
    case invalidManifest(String)
    case corruptCatalogPointer(String)
    case unsupportedCatalogPointerSchema(Int)
    case invalidCatalogPointer(String)
    case orphanedSourceSidecars
    case orphanedLocalSidecars
    case missingLocalCatalog
    case sourceMissing
    case sourceChanged
    case ambiguousPromotion
    case invalidSQLite(String)
    case snapshotMismatch
    case unsafeRollback
    case unsafePath(String)
    case catalogBusy

    var errorDescription: String? {
        switch self {
        case let .corruptManifest(message):
            "The catalog migration manifest is corrupt: \(message)"
        case let .unsupportedManifestSchema(version):
            "Catalog migration manifest version \(version) is not supported."
        case let .invalidManifest(message):
            "The catalog migration manifest is invalid: \(message)"
        case let .corruptCatalogPointer(message):
            "The local catalog pointer is corrupt: \(message)"
        case let .unsupportedCatalogPointerSchema(version):
            "Local catalog pointer version \(version) is not supported."
        case let .invalidCatalogPointer(message):
            "The local catalog pointer is invalid: \(message)"
        case .orphanedSourceSidecars:
            "The package catalog main file is missing while SQLite sidecars remain."
        case .orphanedLocalSidecars:
            "The local catalog main file is missing while SQLite sidecars remain."
        case .missingLocalCatalog:
            "The local catalog for this managed library is missing."
        case .sourceMissing:
            "The authoritative package catalog is missing."
        case .sourceChanged:
            "The package catalog changed while Cadence was cloning it."
        case .ambiguousPromotion:
            "The catalog promotion state is ambiguous; no files were changed."
        case let .invalidSQLite(message):
            "The staged catalog failed SQLite validation: \(message)"
        case .snapshotMismatch:
            "The promoted catalog does not match its validated snapshot."
        case .unsafeRollback:
            "Catalog rollback is unsafe after source cleanup began."
        case let .unsafePath(path):
            "The catalog migration path is unsafe: \(path)"
        case .catalogBusy:
            "This library catalog is already being opened by another transaction."
        }
    }
}

final class LocalCatalogTransactionLock: @unchecked Sendable {
    private static let registry = LocalCatalogTransactionRegistry()

    private let descriptor: Int32
    private let registryKey: String

    private init(descriptor: Int32, registryKey: String) {
        self.descriptor = descriptor
        self.registryKey = registryKey
    }

    deinit {
        _ = Darwin.close(descriptor)
        Self.registry.release(registryKey)
    }

    static func acquire(
        at lockURL: URL,
        trustedRoot: URL,
        fileManager: FileManager
    ) throws -> LocalCatalogTransactionLock {
        try LocalCatalogPathGuard(trustedRoot: trustedRoot)
            .ensureDirectoryChain(
                to: lockURL.deletingLastPathComponent(),
                fileManager: fileManager
            )
        let registryKey = lockURL.standardizedFileURL.path
        guard registry.claim(registryKey) else {
            throw LocalCatalogMigrationError.catalogBusy
        }

        var descriptor: Int32 = -1
        do {
            descriptor = Darwin.open(
                lockURL.path,
                O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
            guard descriptor >= 0 else {
                throw LocalCatalogDurability.posixError()
            }
            var advisoryLock = flock()
            advisoryLock.l_type = Int16(F_WRLCK)
            advisoryLock.l_whence = Int16(SEEK_SET)
            guard Darwin.fcntl(descriptor, F_SETLK, &advisoryLock) != -1 else {
                if errno == EACCES || errno == EAGAIN {
                    throw LocalCatalogMigrationError.catalogBusy
                }
                throw LocalCatalogDurability.posixError()
            }
            return LocalCatalogTransactionLock(
                descriptor: descriptor,
                registryKey: registryKey
            )
        } catch {
            if descriptor >= 0 {
                _ = Darwin.close(descriptor)
            }
            registry.release(registryKey)
            throw error
        }
    }
}

private final class LocalCatalogTransactionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var claimedKeys: Set<String> = []

    func claim(_ key: String) -> Bool {
        lock.withLock {
            guard !claimedKeys.contains(key) else {
                return false
            }
            claimedKeys.insert(key)
            return true
        }
    }

    func release(_ key: String) {
        lock.withLock {
            _ = claimedKeys.remove(key)
        }
    }
}

private struct MissingSourceCatalogContext {
    let package: ManagedLibraryPackage
    let identity: LibraryIdentity
    let localCatalog: LocalLibraryCatalogLocation
    let localPathGuard: LocalCatalogPathGuard
    let hasSourceSidecars: Bool
    let hasCatalogPointer: Bool
}

struct LocalLibraryCatalogMigration: Sendable {
    private static let sourceStoreRelativePath = "Metadata/Library.store"
    private static let catalogPointerFileName = "LocalCatalogPointer.json"
    private static let maximumSourceCloneAttempts = 3
    private static let sqliteSidecarSuffixes = ["-wal", "-shm"]

    private let faultInjector: LocalCatalogMigrationFaultInjector
    private let durability: LocalCatalogDurability

    init(
        faultInjector: LocalCatalogMigrationFaultInjector = .disabled,
        durability: LocalCatalogDurability = .live
    ) {
        self.faultInjector = faultInjector
        self.durability = durability
    }

    func prepareIfNeeded(
        package: ManagedLibraryPackage,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> PreparedLocalLibraryCatalogMigration? {
        let identity = try readLocalCatalogIdentity(package: package, fileManager: fileManager)
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
        let localPathGuard = LocalCatalogPathGuard(trustedRoot: localCatalog.applicationSupportDirectoryURL)
        try localPathGuard.ensureDirectoryChain(
            to: localCatalog.rootURL,
            fileManager: fileManager
        )
        if try localPathGuard.regularFileExists(
            at: localCatalog.migrationManifestURL
        ) {
            var manifest = try loadManifest(from: localCatalog.migrationManifestURL)
            try validate(
                manifest: manifest,
                identity: identity,
                localCatalog: localCatalog,
                fileManager: fileManager
            )
            return try recover(
                manifest: &manifest,
                package: package,
                localCatalog: localCatalog,
                fileManager: fileManager
            )
        }

        let packagePathGuard = LocalCatalogPathGuard(
            trustedRoot: package.location.musicDirectory
        )
        let sourceExists = try packagePathGuard.regularFileExists(
            at: package.metadataStoreURL
        )
        let sourceWALExists = try packagePathGuard.regularFileExists(
            at: sidecarURL(for: package.metadataStoreURL, suffix: "-wal")
        )
        let sourceSHMExists = try packagePathGuard.regularFileExists(
            at: sidecarURL(for: package.metadataStoreURL, suffix: "-shm")
        )
        let catalogPointer = try loadCatalogPointerIfPresent(
            package: package,
            expectedLibraryID: identity.id
        )
        guard sourceExists else {
            return try resolveMissingSourceCatalog(
                MissingSourceCatalogContext(
                    package: package,
                    identity: identity,
                    localCatalog: localCatalog,
                    localPathGuard: localPathGuard,
                    hasSourceSidecars: sourceWALExists || sourceSHMExists,
                    hasCatalogPointer: catalogPointer != nil
                ),
                fileManager: fileManager
            )
        }

        let initialSourceFiles = try captureSourceFiles(
            at: package.metadataStoreURL,
            fileManager: fileManager
        )
        try ensureSafeRoot(localCatalog.rootURL, fileManager: fileManager)
        let operationID = UUID()
        let stagingName = stagingDirectoryName(operationID: operationID)
        let legacyName = fileManager.fileExists(
            atPath: localCatalog.metadataDirectoryURL.path
        ) ? legacyDirectoryName(operationID: operationID) : nil

        var manifest = LocalCatalogMigrationManifest(
            schemaVersion: LocalCatalogMigrationManifest.currentSchemaVersion,
            operationID: operationID,
            libraryID: identity.id,
            origin: .packageSnapshot,
            sourceStoreRelativePath: Self.sourceStoreRelativePath,
            stagingDirectoryName: stagingName,
            legacyDirectoryName: legacyName,
            phase: .prepared,
            sourceFiles: initialSourceFiles,
            stagedSnapshot: nil
        )
        try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
        if legacyName != nil {
            try faultInjector.inject(.afterLegacyMoveIntent)
            try recoverLegacyMoveIfNeeded(
                manifest,
                localCatalog: localCatalog,
                fileManager: fileManager
            )
        }
        return try cloneValidateAndPromote(
            manifest: &manifest,
            package: package,
            localCatalog: localCatalog,
            fileManager: fileManager
        )
    }

    func recordSuccessfulCatalogOpen(
        package: ManagedLibraryPackage,
        libraryID: UUID,
        fileManager: FileManager = .default
    ) throws {
        let identity = try readLocalCatalogIdentity(
            package: package,
            fileManager: fileManager
        )
        guard identity.id == libraryID else {
            throw LocalCatalogMigrationError.invalidCatalogPointer(
                "The opened catalog does not match the package identity."
            )
        }
        try persistCatalogPointer(
            package: package,
            libraryID: libraryID,
            fileManager: fileManager
        )
    }

    func commit(
        _ prepared: PreparedLocalLibraryCatalogMigration,
        fileManager: FileManager = .default
    ) throws {
        var manifest = try loadAndValidate(
            prepared,
            fileManager: fileManager
        )
        try persistCatalogPointer(
            package: prepared.package,
            libraryID: manifest.libraryID,
            fileManager: fileManager
        )
        switch manifest.phase {
        case .complete:
            return
        case .promoted:
            if manifest.origin == .adoptedValidatedLocal {
                manifest.phase = .complete
                try persist(
                    manifest,
                    localCatalog: prepared.localCatalog,
                    fileManager: fileManager
                )
                return
            }
            try verifyAuthoritativeSource(
                manifest,
                package: prepared.package,
                fileManager: fileManager
            )
            manifest.phase = .sourceCleanup
            try persist(
                manifest,
                localCatalog: prepared.localCatalog,
                fileManager: fileManager
            )
            try faultInjector.inject(.afterSourceCleanupIntent)
        case .sourceCleanup:
            guard manifest.origin == .packageSnapshot else {
                throw LocalCatalogMigrationError.invalidManifest(
                    "Only a package snapshot can authorize source cleanup."
                )
            }
        default:
            throw LocalCatalogMigrationError.invalidManifest(
                "Commit requires a promoted catalog."
            )
        }

        try cleanupPackageSource(
            manifest: manifest,
            package: prepared.package,
            localCatalog: prepared.localCatalog,
            fileManager: fileManager
        )
        manifest.phase = .complete
        try persist(
            manifest,
            localCatalog: prepared.localCatalog,
            fileManager: fileManager
        )
    }

    func rollback(
        _ prepared: PreparedLocalLibraryCatalogMigration,
        fileManager: FileManager = .default
    ) throws {
        var manifest = try loadAndValidate(prepared, fileManager: fileManager)
        guard manifest.phase == .promoted,
              manifest.origin == .packageSnapshot
        else {
            throw LocalCatalogMigrationError.unsafeRollback
        }
        try verifyAuthoritativeSource(
            manifest,
            package: prepared.package,
            fileManager: fileManager
        )
        manifest.phase = .rollingBack
        try persist(
            manifest,
            localCatalog: prepared.localCatalog,
            fileManager: fileManager
        )
        try faultInjector.inject(.afterRollbackIntent)
        try finishRollback(
            manifest: &manifest,
            package: prepared.package,
            localCatalog: prepared.localCatalog,
            fileManager: fileManager
        )
    }
}

private extension LocalLibraryCatalogMigration {
    func resolveMissingSourceCatalog(
        _ context: MissingSourceCatalogContext,
        fileManager: FileManager
    ) throws -> PreparedLocalLibraryCatalogMigration? {
        guard !context.hasSourceSidecars else {
            throw LocalCatalogMigrationError.orphanedSourceSidecars
        }
        let localMetadataExists = try context.localPathGuard.directoryExists(
            at: context.localCatalog.metadataDirectoryURL
        )
        let localStoreExists = if localMetadataExists {
            try context.localPathGuard.regularFileExists(
                at: context.localCatalog.storeURL
            )
        } else {
            false
        }
        let localWALExists = if localMetadataExists {
            try context.localPathGuard.regularFileExists(
                at: sidecarURL(for: context.localCatalog.storeURL, suffix: "-wal")
            )
        } else {
            false
        }
        let localSHMExists = if localMetadataExists {
            try context.localPathGuard.regularFileExists(
                at: sidecarURL(for: context.localCatalog.storeURL, suffix: "-shm")
            )
        } else {
            false
        }
        if localStoreExists {
            return try adoptExistingLocalCatalog(
                package: context.package,
                identity: context.identity,
                localCatalog: context.localCatalog,
                fileManager: fileManager
            )
        }
        guard !localWALExists, !localSHMExists else {
            throw LocalCatalogMigrationError.orphanedLocalSidecars
        }
        let hasRetainedMedia = try hasRetainedManagedMedia(
            package: context.package,
            fileManager: fileManager
        )
        guard !context.hasCatalogPointer, !hasRetainedMedia else {
            throw LocalCatalogMigrationError.missingLocalCatalog
        }
        return nil
    }

    func recover(
        manifest: inout LocalCatalogMigrationManifest,
        package: ManagedLibraryPackage,
        localCatalog: LocalLibraryCatalogLocation,
        fileManager: FileManager
    ) throws -> PreparedLocalLibraryCatalogMigration? {
        try validateRecoveryPreconditions(
            manifest,
            localCatalog: localCatalog,
            fileManager: fileManager
        )
        switch manifest.phase {
        case .prepared, .mainCopied, .walHandled,
             .shmDispositionRecorded, .validating:
            guard manifest.origin == .packageSnapshot else {
                throw LocalCatalogMigrationError.invalidManifest(
                    "An adopted catalog cannot be in a cloning phase."
                )
            }
            let stage = stagingDirectoryURL(
                manifest: manifest,
                localCatalog: localCatalog
            )
            if fileManager.fileExists(atPath: stage.path) {
                try rejectSymlink(stage, fileManager: fileManager)
                try fileManager.removeItem(at: stage)
                try durability.syncDirectory(localCatalog.rootURL)
            }
            manifest.phase = .prepared
            manifest.stagedSnapshot = nil
            try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
            return try cloneValidateAndPromote(
                manifest: &manifest,
                package: package,
                localCatalog: localCatalog,
                fileManager: fileManager
            )
        case .validated, .promoting:
            return try finishPromotion(
                manifest: &manifest,
                package: package,
                localCatalog: localCatalog,
                fileManager: fileManager
            )
        case .promoted:
            let snapshot = try requiredSnapshot(manifest)
            try validateSnapshot(
                at: localCatalog.storeURL,
                expected: snapshot,
                fileManager: fileManager
            )
            if manifest.origin == .packageSnapshot {
                try verifyAuthoritativeSource(
                    manifest,
                    package: package,
                    fileManager: fileManager
                )
            }
            return preparedToken(
                manifest: manifest,
                package: package,
                localCatalog: localCatalog
            )
        case .rollingBack:
            try finishRollback(
                manifest: &manifest,
                package: package,
                localCatalog: localCatalog,
                fileManager: fileManager
            )
            return try cloneValidateAndPromote(
                manifest: &manifest,
                package: package,
                localCatalog: localCatalog,
                fileManager: fileManager
            )
        case .sourceCleanup:
            guard fileManager.fileExists(atPath: localCatalog.storeURL.path) else {
                throw LocalCatalogMigrationError.snapshotMismatch
            }
            manifest.stagedSnapshot = try consolidateSQLiteStore(
                at: localCatalog.storeURL,
                fileManager: fileManager
            )
            try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
            return preparedToken(
                manifest: manifest,
                package: package,
                localCatalog: localCatalog
            )
        case .complete:
            guard fileManager.fileExists(atPath: localCatalog.storeURL.path) else {
                throw LocalCatalogMigrationError.snapshotMismatch
            }
            try quickCheckSQLiteStore(at: localCatalog.storeURL)
            return nil
        }
    }

    func validateRecoveryPreconditions(
        _ manifest: LocalCatalogMigrationManifest,
        localCatalog: LocalLibraryCatalogLocation,
        fileManager: FileManager
    ) throws {
        switch manifest.phase {
        case .prepared, .mainCopied, .walHandled,
             .shmDispositionRecorded, .validating, .validated:
            try recoverLegacyMoveIfNeeded(
                manifest,
                localCatalog: localCatalog,
                fileManager: fileManager
            )
        case .promoting, .promoted, .rollingBack, .sourceCleanup, .complete:
            try requirePreservedLegacy(
                manifest,
                localCatalog: localCatalog,
                fileManager: fileManager
            )
        }
    }

    func finishRollback(
        manifest: inout LocalCatalogMigrationManifest,
        package: ManagedLibraryPackage,
        localCatalog: LocalLibraryCatalogLocation,
        fileManager: FileManager
    ) throws {
        guard manifest.phase == .rollingBack,
              manifest.origin == .packageSnapshot
        else {
            throw LocalCatalogMigrationError.unsafeRollback
        }
        try verifyAuthoritativeSource(
            manifest,
            package: package,
            fileManager: fileManager
        )

        if fileManager.fileExists(atPath: localCatalog.metadataDirectoryURL.path) {
            try rejectSymlink(
                localCatalog.metadataDirectoryURL,
                fileManager: fileManager
            )
            try validateSnapshot(
                at: localCatalog.storeURL,
                expected: requiredSnapshot(manifest),
                fileManager: fileManager
            )
            try verifyAuthoritativeSource(
                manifest,
                package: package,
                fileManager: fileManager
            )
            try fileManager.removeItem(at: localCatalog.metadataDirectoryURL)
            try durability.syncDirectory(localCatalog.rootURL)
        }
        try faultInjector.inject(.afterRollbackFinalRemoval)

        let stage = stagingDirectoryURL(
            manifest: manifest,
            localCatalog: localCatalog
        )
        if fileManager.fileExists(atPath: stage.path) {
            try rejectSymlink(stage, fileManager: fileManager)
            try fileManager.removeItem(at: stage)
            try durability.syncDirectory(localCatalog.rootURL)
        }
        try faultInjector.inject(.afterRollbackStageRemoval)
        try faultInjector.inject(.beforeRollbackPrepared)

        manifest.phase = .prepared
        manifest.stagedSnapshot = nil
        try persist(
            manifest,
            localCatalog: localCatalog,
            fileManager: fileManager
        )
        try faultInjector.inject(.afterRollbackPrepared)
    }

    func recoverLegacyMoveIfNeeded(
        _ manifest: LocalCatalogMigrationManifest,
        localCatalog: LocalLibraryCatalogLocation,
        fileManager: FileManager
    ) throws {
        guard let legacyName = manifest.legacyDirectoryName else {
            return
        }
        let legacy = localCatalog.rootURL.appending(
            path: legacyName,
            directoryHint: .isDirectory
        )
        let finalExists = fileManager.fileExists(
            atPath: localCatalog.metadataDirectoryURL.path
        )
        let legacyExists = fileManager.fileExists(atPath: legacy.path)
        switch (finalExists, legacyExists) {
        case (true, false):
            try rejectSymlink(
                localCatalog.metadataDirectoryURL,
                fileManager: fileManager
            )
            try durability.atomicRename(localCatalog.metadataDirectoryURL, legacy)
            try durability.syncDirectory(localCatalog.rootURL)
            try faultInjector.inject(.afterLegacyMoveRename)
        case (false, true):
            try rejectSymlink(legacy, fileManager: fileManager)
        case (true, true), (false, false):
            throw LocalCatalogMigrationError.ambiguousPromotion
        }
    }

    func requirePreservedLegacy(
        _ manifest: LocalCatalogMigrationManifest,
        localCatalog: LocalLibraryCatalogLocation,
        fileManager: FileManager
    ) throws {
        guard let legacyName = manifest.legacyDirectoryName else {
            return
        }
        let legacy = localCatalog.rootURL.appending(
            path: legacyName,
            directoryHint: .isDirectory
        )
        guard fileManager.fileExists(atPath: legacy.path) else {
            throw LocalCatalogMigrationError.ambiguousPromotion
        }
        try rejectSymlink(legacy, fileManager: fileManager)
    }

    func cloneValidateAndPromote(
        manifest: inout LocalCatalogMigrationManifest,
        package: ManagedLibraryPackage,
        localCatalog: LocalLibraryCatalogLocation,
        fileManager: FileManager
    ) throws -> PreparedLocalLibraryCatalogMigration {
        for _ in 0 ..< Self.maximumSourceCloneAttempts {
            let sourceFiles = try captureSourceFiles(
                at: package.metadataStoreURL,
                fileManager: fileManager
            )
            manifest.phase = .prepared
            manifest.sourceFiles = sourceFiles
            manifest.stagedSnapshot = nil
            try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
            try faultInjector.inject(.afterPrepared)

            let stage = stagingDirectoryURL(
                manifest: manifest,
                localCatalog: localCatalog
            )
            if fileManager.fileExists(atPath: stage.path) {
                try rejectSymlink(stage, fileManager: fileManager)
                try fileManager.removeItem(at: stage)
            }
            try fileManager.createDirectory(
                at: stage,
                withIntermediateDirectories: false
            )
            let stagedStore = stage.appending(
                path: "Library.store",
                directoryHint: .notDirectory
            )
            try fileManager.copyItem(at: package.metadataStoreURL, to: stagedStore)
            try durability.syncFile(stagedStore)
            try durability.syncDirectory(stage)
            manifest.phase = .mainCopied
            try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
            try faultInjector.inject(.afterMainCopied)

            let sourceWAL = sidecarURL(for: package.metadataStoreURL, suffix: "-wal")
            if fileManager.fileExists(atPath: sourceWAL.path) {
                let stagedWAL = sidecarURL(for: stagedStore, suffix: "-wal")
                try fileManager.copyItem(at: sourceWAL, to: stagedWAL)
                try durability.syncFile(stagedWAL)
            }
            try durability.syncDirectory(stage)
            manifest.phase = .walHandled
            try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
            try faultInjector.inject(.afterWALHandled)

            manifest.phase = .shmDispositionRecorded
            try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
            try faultInjector.inject(.afterSHMDispositionRecorded)

            let afterCopy = try captureSourceFiles(
                at: package.metadataStoreURL,
                fileManager: fileManager
            )
            guard durableSourceFilesMatch(sourceFiles, afterCopy) else {
                try fileManager.removeItem(at: stage)
                try durability.syncDirectory(localCatalog.rootURL)
                continue
            }

            manifest.phase = .validating
            try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
            manifest.stagedSnapshot = try consolidateSQLiteStore(
                at: stagedStore,
                fileManager: fileManager
            )
            manifest.phase = .validated
            try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
            try faultInjector.inject(.afterValidated)
            return try finishPromotion(
                manifest: &manifest,
                package: package,
                localCatalog: localCatalog,
                fileManager: fileManager
            )
        }
        throw LocalCatalogMigrationError.sourceChanged
    }

    func finishPromotion(
        manifest: inout LocalCatalogMigrationManifest,
        package: ManagedLibraryPackage,
        localCatalog: LocalLibraryCatalogLocation,
        fileManager: FileManager
    ) throws -> PreparedLocalLibraryCatalogMigration {
        let snapshot = try requiredSnapshot(manifest)
        let stage = stagingDirectoryURL(
            manifest: manifest,
            localCatalog: localCatalog
        )
        let final = localCatalog.metadataDirectoryURL
        let stageExists = fileManager.fileExists(atPath: stage.path)
        let finalExists = fileManager.fileExists(atPath: final.path)

        if manifest.phase == .validated {
            try validateSnapshot(
                at: stage.appending(path: "Library.store"),
                expected: snapshot,
                fileManager: fileManager
            )
            manifest.phase = .promoting
            try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
            try faultInjector.inject(.afterPromotionIntent)
        }

        switch (stageExists, finalExists) {
        case (true, false):
            try validateSnapshot(
                at: stage.appending(path: "Library.store"),
                expected: snapshot,
                fileManager: fileManager
            )
            try durability.atomicRename(stage, final)
            try durability.syncDirectory(localCatalog.rootURL)
            try faultInjector.inject(.afterPromotionRename)
        case (false, true):
            try validateSnapshot(
                at: localCatalog.storeURL,
                expected: snapshot,
                fileManager: fileManager
            )
            try durability.syncDirectory(localCatalog.rootURL)
        case (true, true), (false, false):
            throw LocalCatalogMigrationError.ambiguousPromotion
        }

        manifest.phase = .promoted
        try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
        try faultInjector.inject(.afterPromoted)
        if manifest.origin == .packageSnapshot {
            try verifyAuthoritativeSource(
                manifest,
                package: package,
                fileManager: fileManager
            )
        }
        return preparedToken(
            manifest: manifest,
            package: package,
            localCatalog: localCatalog
        )
    }

    func adoptExistingLocalCatalog(
        package: ManagedLibraryPackage,
        identity: LibraryIdentity,
        localCatalog: LocalLibraryCatalogLocation,
        fileManager: FileManager
    ) throws -> PreparedLocalLibraryCatalogMigration {
        try ensureSafeRoot(localCatalog.rootURL, fileManager: fileManager)
        try rejectSymlink(localCatalog.metadataDirectoryURL, fileManager: fileManager)
        let snapshot = try consolidateSQLiteStore(
            at: localCatalog.storeURL,
            fileManager: fileManager
        )
        let operationID = UUID()
        let manifest = LocalCatalogMigrationManifest(
            schemaVersion: LocalCatalogMigrationManifest.currentSchemaVersion,
            operationID: operationID,
            libraryID: identity.id,
            origin: .adoptedValidatedLocal,
            sourceStoreRelativePath: nil,
            stagingDirectoryName: stagingDirectoryName(operationID: operationID),
            legacyDirectoryName: nil,
            phase: .promoted,
            sourceFiles: [],
            stagedSnapshot: snapshot
        )
        try persist(manifest, localCatalog: localCatalog, fileManager: fileManager)
        try faultInjector.inject(.afterPromoted)
        return preparedToken(
            manifest: manifest,
            package: package,
            localCatalog: localCatalog
        )
    }

    func catalogPointerURL(
        for package: ManagedLibraryPackage
    ) -> URL {
        package.metadataDirectoryURL.appending(
            path: Self.catalogPointerFileName,
            directoryHint: .notDirectory
        )
    }

    func loadCatalogPointerIfPresent(
        package: ManagedLibraryPackage,
        expectedLibraryID: UUID
    ) throws -> LocalCatalogPointer? {
        let url = catalogPointerURL(for: package)
        let pathGuard = LocalCatalogPathGuard(
            trustedRoot: package.location.musicDirectory
        )
        guard try pathGuard.regularFileExists(at: url) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LocalCatalogMigrationError.corruptCatalogPointer(
                error.localizedDescription
            )
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any],
                  let version = dictionary["schemaVersion"] as? Int
            else {
                throw LocalCatalogMigrationError.corruptCatalogPointer(
                    "schemaVersion is missing."
                )
            }
            guard version == LocalCatalogPointer.currentSchemaVersion else {
                throw LocalCatalogMigrationError.unsupportedCatalogPointerSchema(
                    version
                )
            }
            let pointer = try JSONDecoder().decode(
                LocalCatalogPointer.self,
                from: data
            )
            guard pointer.libraryID == expectedLibraryID else {
                throw LocalCatalogMigrationError.invalidCatalogPointer(
                    "The library identity does not match."
                )
            }
            return pointer
        } catch let error as LocalCatalogMigrationError {
            throw error
        } catch {
            throw LocalCatalogMigrationError.corruptCatalogPointer(
                error.localizedDescription
            )
        }
    }

    func persistCatalogPointer(
        package: ManagedLibraryPackage,
        libraryID: UUID,
        fileManager: FileManager
    ) throws {
        let expected = LocalCatalogPointer(
            schemaVersion: LocalCatalogPointer.currentSchemaVersion,
            libraryID: libraryID
        )
        if let existing = try loadCatalogPointerIfPresent(
            package: package,
            expectedLibraryID: libraryID
        ) {
            guard existing == expected else {
                throw LocalCatalogMigrationError.invalidCatalogPointer(
                    "The durable pointer does not match the opened catalog."
                )
            }
            return
        }

        let pathGuard = LocalCatalogPathGuard(
            trustedRoot: package.location.musicDirectory
        )
        try pathGuard.validateDirectoryChain(to: package.metadataDirectoryURL)
        let destination = catalogPointerURL(for: package)
        let temporaryURL = package.metadataDirectoryURL.appending(
            path: ".LocalCatalogPointer-\(UUID().uuidString).tmp",
            directoryHint: .notDirectory
        )
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }
        let temporaryExists = try pathGuard.regularFileExists(at: temporaryURL)
        guard !temporaryExists else {
            throw LocalCatalogMigrationError.unsafePath(temporaryURL.path)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(expected).write(to: temporaryURL)
        guard try pathGuard.regularFileExists(at: temporaryURL) else {
            throw LocalCatalogMigrationError.unsafePath(temporaryURL.path)
        }
        try durability.syncFile(temporaryURL)
        do {
            try durability.atomicRename(temporaryURL, destination)
        } catch LocalCatalogMigrationError.ambiguousPromotion {
            guard try loadCatalogPointerIfPresent(
                package: package,
                expectedLibraryID: libraryID
            ) == expected else {
                throw LocalCatalogMigrationError.invalidCatalogPointer(
                    "Another catalog pointer appeared during persistence."
                )
            }
            return
        }
        try durability.syncFile(destination)
        try durability.syncDirectory(package.metadataDirectoryURL)
        guard try loadCatalogPointerIfPresent(
            package: package,
            expectedLibraryID: libraryID
        ) == expected else {
            throw LocalCatalogMigrationError.corruptCatalogPointer(
                "The durable read-back did not match the write."
            )
        }
    }

    func hasRetainedManagedMedia(
        package: ManagedLibraryPackage,
        fileManager: FileManager
    ) throws -> Bool {
        let pathGuard = LocalCatalogPathGuard(
            trustedRoot: package.location.musicDirectory
        )
        guard try pathGuard.directoryExists(at: package.mediaDirectoryURL) else {
            return false
        }
        do {
            return try fileManager.contentsOfDirectory(
                atPath: package.mediaDirectoryURL.path
            ).contains { !$0.hasPrefix(".") }
        } catch {
            throw LocalCatalogMigrationError.unsafePath(
                package.mediaDirectoryURL.path
            )
        }
    }

    func cleanupPackageSource(
        manifest: LocalCatalogMigrationManifest,
        package: ManagedLibraryPackage,
        localCatalog: LocalLibraryCatalogLocation,
        fileManager: FileManager
    ) throws {
        guard manifest.origin == .packageSnapshot,
              manifest.phase == .sourceCleanup
        else {
            throw LocalCatalogMigrationError.invalidManifest(
                "Package cleanup requires durable package-source authority."
            )
        }
        let pathGuard = LocalCatalogPathGuard(
            trustedRoot: package.location.musicDirectory
        )
        try pathGuard.validateDirectoryChain(to: package.metadataDirectoryURL)
        let removals: [(URL, LocalCatalogMigrationFailurePoint)] = [
            (package.metadataStoreURL, .afterSourceMainRemoved),
            (
                sidecarURL(for: package.metadataStoreURL, suffix: "-wal"),
                .afterSourceWALRemoved
            ),
            (
                sidecarURL(for: package.metadataStoreURL, suffix: "-shm"),
                .afterSourceSHMRemoved
            ),
            (package.lyricsSearchDatabaseURL, .afterSearchMainRemoved),
            (
                sidecarURL(for: package.lyricsSearchDatabaseURL, suffix: "-wal"),
                .afterSearchWALRemoved
            ),
            (
                sidecarURL(for: package.lyricsSearchDatabaseURL, suffix: "-shm"),
                .afterSearchSHMRemoved
            ),
        ]
        for (url, point) in removals {
            if fileManager.fileExists(atPath: url.path) {
                guard try pathGuard.regularFileExists(at: url) else {
                    throw LocalCatalogMigrationError.unsafePath(url.path)
                }
                try rejectSymlink(url, fileManager: fileManager)
                try fileManager.removeItem(at: url)
                try durability.syncDirectory(url.deletingLastPathComponent())
            }
            try faultInjector.inject(point)
        }
        try durability.syncDirectory(package.metadataDirectoryURL)
        try durability.syncDirectory(localCatalog.rootURL)
    }

    func captureSourceFiles(
        at storeURL: URL,
        fileManager: FileManager
    ) throws -> [LocalCatalogMigrationManifest.SourceFile] {
        let trustedRoot = storeURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pathGuard = LocalCatalogPathGuard(trustedRoot: trustedRoot)
        guard try pathGuard.regularFileExists(at: storeURL) else {
            throw LocalCatalogMigrationError.sourceMissing
        }
        try rejectSymlink(storeURL, fileManager: fileManager)
        let main = try fingerprint(at: storeURL, fileManager: fileManager)
        let walURL = sidecarURL(for: storeURL, suffix: "-wal")
        _ = try pathGuard.regularFileExists(at: walURL)
        let wal = try optionalFingerprint(at: walURL, fileManager: fileManager)
        let shmURL = sidecarURL(for: storeURL, suffix: "-shm")
        _ = try pathGuard.regularFileExists(at: shmURL)
        let shm = try optionalFingerprint(at: shmURL, fileManager: fileManager)
        return [
            LocalCatalogMigrationManifest.SourceFile(
                role: .main,
                disposition: .copied,
                byteCount: main.byteCount,
                sha256: main.sha256
            ),
            LocalCatalogMigrationManifest.SourceFile(
                role: .wal,
                disposition: wal == nil ? .absent : .copied,
                byteCount: wal?.byteCount,
                sha256: wal?.sha256
            ),
            LocalCatalogMigrationManifest.SourceFile(
                role: .shm,
                disposition: shm == nil ? .absent : .rebuild,
                byteCount: shm?.byteCount,
                sha256: shm?.sha256
            ),
        ]
    }

    func verifyAuthoritativeSource(
        _ manifest: LocalCatalogMigrationManifest,
        package: ManagedLibraryPackage,
        fileManager: FileManager
    ) throws {
        let current = try captureSourceFiles(
            at: package.metadataStoreURL,
            fileManager: fileManager
        )
        guard durableSourceFilesMatch(manifest.sourceFiles, current) else {
            throw LocalCatalogMigrationError.sourceChanged
        }
    }

    func durableSourceFilesMatch(
        _ lhs: [LocalCatalogMigrationManifest.SourceFile],
        _ rhs: [LocalCatalogMigrationManifest.SourceFile]
    ) -> Bool {
        lhs.filter { $0.role != .shm } == rhs.filter { $0.role != .shm }
    }

    func consolidateSQLiteStore(
        at storeURL: URL,
        fileManager: FileManager
    ) throws -> LocalCatalogMigrationManifest.Snapshot {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            throw LocalCatalogMigrationError.sourceMissing
        }
        try rejectSymlink(storeURL, fileManager: fileManager)
        var configuration = Configuration()
        configuration.label = "Cadence.LocalCatalogMigration"
        let database = try DatabaseQueue(
            path: storeURL.path,
            configuration: configuration
        )
        do {
            let quickCheck = try database.read { database in
                try String.fetchOne(database, sql: "PRAGMA quick_check")
            }
            guard quickCheck == "ok" else {
                throw LocalCatalogMigrationError.invalidSQLite(
                    quickCheck ?? "no quick_check result"
                )
            }
            _ = try database.writeWithoutTransaction { database in
                try database.checkpoint(.truncate)
            }
            try database.close()
        } catch {
            try? database.close()
            throw error
        }

        try removeSQLiteSidecars(at: storeURL, fileManager: fileManager)
        try durability.syncFile(storeURL)
        try durability.syncDirectory(storeURL.deletingLastPathComponent())
        try quickCheckSQLiteStore(at: storeURL)
        try removeSQLiteSidecars(at: storeURL, fileManager: fileManager)
        try durability.syncDirectory(storeURL.deletingLastPathComponent())
        let digest = try fingerprint(at: storeURL, fileManager: fileManager)
        return LocalCatalogMigrationManifest.Snapshot(
            byteCount: digest.byteCount,
            sha256: digest.sha256,
            quickCheck: "ok"
        )
    }

    func quickCheckSQLiteStore(at storeURL: URL) throws {
        var configuration = Configuration()
        configuration.label = "Cadence.LocalCatalogMigration.Validation"
        let database = try DatabaseQueue(
            path: storeURL.path,
            configuration: configuration
        )
        do {
            let result = try database.read { database in
                try String.fetchOne(database, sql: "PRAGMA quick_check")
            }
            try database.close()
            guard result == "ok" else {
                throw LocalCatalogMigrationError.invalidSQLite(
                    result ?? "no quick_check result"
                )
            }
        } catch {
            try? database.close()
            throw error
        }
    }

    func validateSnapshot(
        at storeURL: URL,
        expected: LocalCatalogMigrationManifest.Snapshot,
        fileManager: FileManager
    ) throws {
        guard expected.quickCheck == "ok" else {
            throw LocalCatalogMigrationError.invalidManifest(
                "The snapshot quick_check result is not ok."
            )
        }
        for suffix in Self.sqliteSidecarSuffixes {
            guard !fileManager.fileExists(
                atPath: sidecarURL(for: storeURL, suffix: suffix).path
            ) else {
                throw LocalCatalogMigrationError.snapshotMismatch
            }
        }
        try quickCheckSQLiteStore(at: storeURL)
        try removeSQLiteSidecars(at: storeURL, fileManager: fileManager)
        try durability.syncDirectory(storeURL.deletingLastPathComponent())
        let actual = try fingerprint(at: storeURL, fileManager: fileManager)
        guard actual.byteCount == expected.byteCount,
              actual.sha256 == expected.sha256
        else {
            throw LocalCatalogMigrationError.snapshotMismatch
        }
    }

    func persist(
        _ manifest: LocalCatalogMigrationManifest,
        localCatalog: LocalLibraryCatalogLocation,
        fileManager: FileManager
    ) throws {
        try ensureSafeRoot(localCatalog.rootURL, fileManager: fileManager)
        if fileManager.fileExists(atPath: localCatalog.migrationManifestURL.path) {
            try rejectSymlink(
                localCatalog.migrationManifestURL,
                fileManager: fileManager
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        let temporaryURL = localCatalog.rootURL.appending(
            path: ".CatalogMigration-\(manifest.operationID.uuidString)-\(UUID().uuidString).tmp",
            directoryHint: .notDirectory
        )
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }
        try data.write(to: temporaryURL)
        try durability.syncFile(temporaryURL)
        try replaceManifest(
            temporaryURL,
            destination: localCatalog.migrationManifestURL,
            fileManager: fileManager
        )
        try durability.syncFile(localCatalog.migrationManifestURL)
        try durability.syncDirectory(localCatalog.rootURL)
        let readBack = try JSONDecoder().decode(
            LocalCatalogMigrationManifest.self,
            from: Data(contentsOf: localCatalog.migrationManifestURL)
        )
        guard readBack == manifest else {
            throw LocalCatalogMigrationError.corruptManifest(
                "The durable read-back did not match the write."
            )
        }
    }

    func replaceManifest(
        _ source: URL,
        destination: URL,
        fileManager: FileManager
    ) throws {
        try rejectSymlink(source, fileManager: fileManager)
        if fileManager.fileExists(atPath: destination.path) {
            try rejectSymlink(destination, fileManager: fileManager)
        }
        var sourceInfo = stat()
        guard Darwin.lstat(source.path, &sourceInfo) == 0 else {
            throw LocalCatalogDurability.posixError()
        }
        var parentInfo = stat()
        guard Darwin.lstat(
            destination.deletingLastPathComponent().path,
            &parentInfo
        ) == 0 else {
            throw LocalCatalogDurability.posixError()
        }
        guard sourceInfo.st_dev == parentInfo.st_dev else {
            throw LocalCatalogMigrationError.unsafePath(destination.path)
        }
        guard Darwin.rename(source.path, destination.path) == 0 else {
            throw LocalCatalogDurability.posixError()
        }
    }

    func loadManifest(
        from url: URL
    ) throws -> LocalCatalogMigrationManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LocalCatalogMigrationError.corruptManifest(
                error.localizedDescription
            )
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any],
                  let version = dictionary["schemaVersion"] as? Int
            else {
                throw LocalCatalogMigrationError.corruptManifest(
                    "schemaVersion is missing."
                )
            }
            guard version == LocalCatalogMigrationManifest.currentSchemaVersion else {
                throw LocalCatalogMigrationError.unsupportedManifestSchema(version)
            }
            return try JSONDecoder().decode(
                LocalCatalogMigrationManifest.self,
                from: data
            )
        } catch let error as LocalCatalogMigrationError {
            throw error
        } catch {
            throw LocalCatalogMigrationError.corruptManifest(
                error.localizedDescription
            )
        }
    }

    func loadAndValidate(
        _ prepared: PreparedLocalLibraryCatalogMigration,
        fileManager: FileManager
    ) throws -> LocalCatalogMigrationManifest {
        let pathGuard = LocalCatalogPathGuard(
            trustedRoot: prepared.localCatalog.applicationSupportDirectoryURL
        )
        guard try pathGuard.regularFileExists(
            at: prepared.localCatalog.migrationManifestURL
        ) else {
            throw LocalCatalogMigrationError.unsafePath(
                prepared.localCatalog.migrationManifestURL.path
            )
        }
        let manifest = try loadManifest(
            from: prepared.localCatalog.migrationManifestURL
        )
        let identity = try readLocalCatalogIdentity(
            package: prepared.package,
            fileManager: fileManager
        )
        try validate(
            manifest: manifest,
            identity: identity,
            localCatalog: prepared.localCatalog,
            fileManager: fileManager
        )
        guard manifest.operationID == prepared.operationID,
              manifest.libraryID == prepared.libraryID
        else {
            throw LocalCatalogMigrationError.invalidManifest(
                "The prepared token does not match the durable operation."
            )
        }
        return manifest
    }

    func validate(
        manifest: LocalCatalogMigrationManifest,
        identity: LibraryIdentity,
        localCatalog: LocalLibraryCatalogLocation,
        fileManager: FileManager
    ) throws {
        guard manifest.schemaVersion
            == LocalCatalogMigrationManifest.currentSchemaVersion
        else {
            throw LocalCatalogMigrationError.unsupportedManifestSchema(
                manifest.schemaVersion
            )
        }
        guard manifest.libraryID == identity.id else {
            throw LocalCatalogMigrationError.invalidManifest(
                "The library identity does not match."
            )
        }
        guard manifest.stagingDirectoryName
            == stagingDirectoryName(operationID: manifest.operationID)
        else {
            throw LocalCatalogMigrationError.unsafePath(
                manifest.stagingDirectoryName
            )
        }
        if let legacy = manifest.legacyDirectoryName {
            guard legacy == legacyDirectoryName(operationID: manifest.operationID) else {
                throw LocalCatalogMigrationError.unsafePath(legacy)
            }
        }
        try validateSemanticManifest(manifest)
        try ensureSafeRoot(localCatalog.rootURL, fileManager: fileManager)
        let pathGuard = LocalCatalogPathGuard(
            trustedRoot: localCatalog.applicationSupportDirectoryURL
        )
        if try pathGuard.directoryExists(at: localCatalog.metadataDirectoryURL) {
            _ = try pathGuard.regularFileExists(at: localCatalog.storeURL)
            for suffix in Self.sqliteSidecarSuffixes {
                _ = try pathGuard.regularFileExists(
                    at: sidecarURL(for: localCatalog.storeURL, suffix: suffix)
                )
            }
        }
        for url in [
            stagingDirectoryURL(manifest: manifest, localCatalog: localCatalog),
            manifest.legacyDirectoryName.map {
                localCatalog.rootURL.appending(path: $0, directoryHint: .isDirectory)
            },
            localCatalog.metadataDirectoryURL,
        ].compactMap(\.self) where fileManager.fileExists(atPath: url.path) {
            try rejectSymlink(url, fileManager: fileManager)
        }
    }

    func validateSemanticManifest(
        _ manifest: LocalCatalogMigrationManifest
    ) throws {
        switch manifest.origin {
        case .packageSnapshot:
            guard manifest.sourceStoreRelativePath == Self.sourceStoreRelativePath else {
                throw LocalCatalogMigrationError.invalidManifest(
                    "The package source path is invalid."
                )
            }
            try validatePackageSourceFiles(manifest.sourceFiles)
            switch manifest.phase {
            case .prepared, .mainCopied, .walHandled,
                 .shmDispositionRecorded, .validating:
                guard manifest.stagedSnapshot == nil else {
                    throw LocalCatalogMigrationError.invalidManifest(
                        "A snapshot exists before validation completed."
                    )
                }
            case .validated, .promoting, .promoted, .rollingBack,
                 .sourceCleanup, .complete:
                try validateSnapshotSemantics(requiredSnapshot(manifest))
            }
        case .adoptedValidatedLocal:
            guard manifest.sourceStoreRelativePath == nil,
                  manifest.sourceFiles.isEmpty,
                  manifest.legacyDirectoryName == nil
            else {
                throw LocalCatalogMigrationError.invalidManifest(
                    "An adopted catalog contains package migration fields."
                )
            }
            guard manifest.phase == .promoted || manifest.phase == .complete else {
                throw LocalCatalogMigrationError.invalidManifest(
                    "An adopted catalog has an impossible migration phase."
                )
            }
            try validateSnapshotSemantics(requiredSnapshot(manifest))
        }
    }

    func validatePackageSourceFiles(
        _ sourceFiles: [LocalCatalogMigrationManifest.SourceFile]
    ) throws {
        let mainFiles = sourceFiles.filter { $0.role == .main }
        let walFiles = sourceFiles.filter { $0.role == .wal }
        let shmFiles = sourceFiles.filter { $0.role == .shm }
        guard sourceFiles.count == 3,
              mainFiles.count == 1,
              walFiles.count == 1,
              shmFiles.count == 1
        else {
            throw LocalCatalogMigrationError.invalidManifest(
                "The package source-file roles are incomplete or duplicated."
            )
        }

        let main = mainFiles[0]
        guard main.disposition == .copied else {
            throw LocalCatalogMigrationError.invalidManifest(
                "The package main store must be copied."
            )
        }
        try validatePresentFingerprint(main, label: "main store")

        let wal = walFiles[0]
        switch wal.disposition {
        case .copied:
            try validatePresentFingerprint(wal, label: "WAL")
        case .absent:
            try validateAbsentFingerprint(wal, label: "WAL")
        case .rebuild:
            throw LocalCatalogMigrationError.invalidManifest(
                "A package WAL cannot be marked for rebuild."
            )
        }

        let shm = shmFiles[0]
        switch shm.disposition {
        case .rebuild:
            try validatePresentFingerprint(shm, label: "SHM")
        case .absent:
            try validateAbsentFingerprint(shm, label: "SHM")
        case .copied:
            throw LocalCatalogMigrationError.invalidManifest(
                "A package SHM cannot be copied."
            )
        }
    }

    func validatePresentFingerprint(
        _ sourceFile: LocalCatalogMigrationManifest.SourceFile,
        label: String
    ) throws {
        guard let byteCount = sourceFile.byteCount,
              byteCount >= 0,
              let sha256 = sourceFile.sha256,
              isCanonicalSHA256(sha256)
        else {
            throw LocalCatalogMigrationError.invalidManifest(
                "The \(label) fingerprint is invalid."
            )
        }
    }

    func validateAbsentFingerprint(
        _ sourceFile: LocalCatalogMigrationManifest.SourceFile,
        label: String
    ) throws {
        guard sourceFile.byteCount == nil, sourceFile.sha256 == nil else {
            throw LocalCatalogMigrationError.invalidManifest(
                "The absent \(label) contains a fingerprint."
            )
        }
    }

    func validateSnapshotSemantics(
        _ snapshot: LocalCatalogMigrationManifest.Snapshot
    ) throws {
        guard snapshot.byteCount >= 0,
              isCanonicalSHA256(snapshot.sha256),
              snapshot.quickCheck == "ok"
        else {
            throw LocalCatalogMigrationError.invalidManifest(
                "The validated catalog snapshot is malformed."
            )
        }
    }

    func isCanonicalSHA256(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 64 && bytes.allSatisfy { byte in
            (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
        }
    }

    func ensureSafeRoot(
        _ rootURL: URL,
        fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: rootURL.path) {
            try rejectSymlink(rootURL, fileManager: fileManager)
        } else {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
            try durability.syncDirectory(rootURL.deletingLastPathComponent())
        }
    }

    func rejectSymlink(
        _ url: URL,
        fileManager _: FileManager
    ) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw LocalCatalogMigrationError.unsafePath(url.path)
        }
    }

    func fingerprint(
        at url: URL,
        fileManager: FileManager
    ) throws -> (byteCount: Int64, sha256: String) {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw LocalCatalogMigrationError.unsafePath(url.path)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        let digest = hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
        return (size.int64Value, digest)
    }

    func optionalFingerprint(
        at url: URL,
        fileManager: FileManager
    ) throws -> (byteCount: Int64, sha256: String)? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        try rejectSymlink(url, fileManager: fileManager)
        return try fingerprint(at: url, fileManager: fileManager)
    }

    func removeSQLiteSidecars(
        at storeURL: URL,
        fileManager: FileManager
    ) throws {
        for suffix in Self.sqliteSidecarSuffixes {
            let sidecar = sidecarURL(for: storeURL, suffix: suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try rejectSymlink(sidecar, fileManager: fileManager)
                try fileManager.removeItem(at: sidecar)
            }
        }
    }

    func requiredSnapshot(
        _ manifest: LocalCatalogMigrationManifest
    ) throws -> LocalCatalogMigrationManifest.Snapshot {
        guard let snapshot = manifest.stagedSnapshot else {
            throw LocalCatalogMigrationError.invalidManifest(
                "The validated snapshot is missing."
            )
        }
        return snapshot
    }

    func preparedToken(
        manifest: LocalCatalogMigrationManifest,
        package: ManagedLibraryPackage,
        localCatalog: LocalLibraryCatalogLocation
    ) -> PreparedLocalLibraryCatalogMigration {
        PreparedLocalLibraryCatalogMigration(
            package: package,
            localCatalog: localCatalog,
            operationID: manifest.operationID,
            libraryID: manifest.libraryID
        )
    }

    func stagingDirectoryName(operationID: UUID) -> String {
        ".Metadata-\(operationID.uuidString).staging"
    }

    func legacyDirectoryName(operationID: UUID) -> String {
        ".Metadata-\(operationID.uuidString).legacy"
    }

    func stagingDirectoryURL(
        manifest: LocalCatalogMigrationManifest,
        localCatalog: LocalLibraryCatalogLocation
    ) -> URL {
        localCatalog.rootURL.appending(
            path: manifest.stagingDirectoryName,
            directoryHint: .isDirectory
        )
    }

    func sidecarURL(for storeURL: URL, suffix: String) -> URL {
        URL(filePath: storeURL.path + suffix)
    }
}

private extension LocalCatalogDurability {
    static func syncFileLive(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw posixError()
        }
        defer { Darwin.close(descriptor) }
        if Darwin.fcntl(descriptor, F_FULLFSYNC) == -1,
           Darwin.fsync(descriptor) == -1 {
            throw posixError()
        }
    }

    static func syncDirectoryLive(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw posixError()
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw posixError()
        }
    }

    static func atomicRenameLive(_ source: URL, _ destination: URL) throws {
        var sourceInfo = stat()
        guard Darwin.lstat(source.path, &sourceInfo) == 0 else {
            throw posixError()
        }
        var parentInfo = stat()
        guard Darwin.lstat(destination.deletingLastPathComponent().path, &parentInfo) == 0 else {
            throw posixError()
        }
        guard sourceInfo.st_dev == parentInfo.st_dev else {
            throw LocalCatalogMigrationError.unsafePath(destination.path)
        }
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                Darwin.renameatx_np(
                    AT_FDCWD,
                    sourcePath,
                    AT_FDCWD,
                    destinationPath,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else {
            if errno == EEXIST {
                throw LocalCatalogMigrationError.ambiguousPromotion
            }
            throw posixError()
        }
    }

    static func posixError() -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: nil
        )
    }
}
