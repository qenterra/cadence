@testable import Cadence
import Darwin
import Foundation
import SwiftData
import Testing

@_silgen_name("fork")
private func cadenceTestFork() -> pid_t

enum CatalogMigrationTestInterruption: Error {
    case injected
}

enum ManifestDamage: String, CaseIterable {
    case corrupt
    case future
}

struct CatalogPointerFixture: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let libraryID: UUID
}

enum CatalogPointerDamage: String, CaseIterable, Sendable {
    case corrupt
    case futureSchema
    case wrongLibrary

    var expectedErrorPrefix: String {
        switch self {
        case .corrupt:
            "corruptCatalogPointer"
        case .futureSchema:
            "unsupportedCatalogPointerSchema"
        case .wrongLibrary:
            "invalidCatalogPointer"
        }
    }

    func bytes(libraryID: UUID) throws -> Data {
        switch self {
        case .corrupt:
            Data("not-a-catalog-pointer".utf8)
        case .futureSchema:
            try JSONEncoder().encode(
                CatalogPointerFixture(
                    schemaVersion: 2,
                    libraryID: libraryID
                )
            )
        case .wrongLibrary:
            try JSONEncoder().encode(
                CatalogPointerFixture(
                    schemaVersion: 1,
                    libraryID: UUID()
                )
            )
        }
    }
}

enum LocalOrphanSidecarSet: String, CaseIterable, Sendable {
    case wal
    case shm
    case both

    var suffixes: [String] {
        switch self {
        case .wal:
            ["-wal"]
        case .shm:
            ["-shm"]
        case .both:
            ["-wal", "-shm"]
        }
    }
}

enum RollbackBoundary: String, CaseIterable, Sendable {
    case afterRollbackIntent
    case afterRollbackFinalRemoval
    case afterRollbackStageRemoval
    case beforeRollbackPrepared
    case afterRollbackPrepared
}

struct RollbackCrashScenario: Sendable {
    let boundary: RollbackBoundary
    let preservesLegacy: Bool

    static let allCases = RollbackBoundary.allCases.flatMap { boundary in
        [false, true].map { preservesLegacy in
            RollbackCrashScenario(
                boundary: boundary,
                preservesLegacy: preservesLegacy
            )
        }
    }
}

enum LocalAncestorRedirect: String, CaseIterable, Sendable {
    case cadence
    case libraries
    case identityRoot

    func install(
        in fixture: MigrationFixture,
        destination: URL
    ) throws {
        let cadence = fixture.applicationSupportDirectory.appending(
            path: "Cadence",
            directoryHint: .isDirectory
        )
        let libraries = cadence.appending(
            path: "Libraries",
            directoryHint: .isDirectory
        )
        switch self {
        case .cadence:
            try FileManager.default.createSymbolicLink(
                at: cadence,
                withDestinationURL: destination
            )
        case .libraries:
            try FileManager.default.createDirectory(
                at: cadence,
                withIntermediateDirectories: false
            )
            try FileManager.default.createSymbolicLink(
                at: libraries,
                withDestinationURL: destination
            )
        case .identityRoot:
            try FileManager.default.createDirectory(
                at: libraries,
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                at: fixture.localCatalog.rootURL,
                withDestinationURL: destination
            )
        }
    }
}

enum SemanticManifestDamage: String, CaseIterable, Sendable {
    case adoptedPrepared
    case adoptedMainCopied
    case adoptedWALHandled
    case adoptedSHMDispositionRecorded
    case adoptedValidating
    case adoptedValidated
    case adoptedPromoting
    case missingMain
    case duplicateMain
    case missingWAL
    case missingSHM
    case absentMain
    case rebuiltWAL
    case copiedSHM
    case negativeMainSize
    case malformedMainDigest
    case copiedWALWithoutFingerprint
    case absentWALWithFingerprint
    case rebuiltSHMWithoutFingerprint
    case snapshotBeforeValidation
    case missingValidatedSnapshot
    case negativeSnapshotSize
    case malformedSnapshotDigest

    func apply(
        to manifest: LocalCatalogMigrationManifest
    ) -> LocalCatalogMigrationManifest {
        var mutation = SemanticManifestMutation(manifest)
        applyAdoptionDamage(to: &mutation)
        applySourceFileMembershipDamage(to: &mutation)
        applySourceFileMetadataDamage(to: &mutation)
        applySnapshotDamage(to: &mutation)
        return mutation.result
    }

    private func applyAdoptionDamage(
        to mutation: inout SemanticManifestMutation
    ) {
        switch self {
        case .adoptedPrepared:
            mutation.adopt(
                phase: .prepared,
                clearsSnapshot: true
            )
        case .adoptedMainCopied:
            mutation.adopt(
                phase: .mainCopied,
                clearsSnapshot: true
            )
        case .adoptedWALHandled:
            mutation.adopt(
                phase: .walHandled,
                clearsSnapshot: true
            )
        case .adoptedSHMDispositionRecorded:
            mutation.adopt(
                phase: .shmDispositionRecorded,
                clearsSnapshot: true
            )
        case .adoptedValidating:
            mutation.adopt(
                phase: .validating,
                clearsSnapshot: true
            )
        case .adoptedValidated:
            mutation.adopt(
                phase: .validated,
                clearsSnapshot: false
            )
        case .adoptedPromoting:
            mutation.adopt(
                phase: .promoting,
                clearsSnapshot: false
            )
        default:
            break
        }
    }

    private func applySourceFileMembershipDamage(
        to mutation: inout SemanticManifestMutation
    ) {
        switch self {
        case .missingMain:
            mutation.sourceFiles.removeAll { $0.role == .main }
        case .duplicateMain:
            if let main = mutation.sourceFiles.first(where: { $0.role == .main }) {
                mutation.sourceFiles.append(main)
            }
        case .missingWAL:
            mutation.sourceFiles.removeAll { $0.role == .wal }
        case .missingSHM:
            mutation.sourceFiles.removeAll { $0.role == .shm }
        default:
            break
        }
    }

    private func applySourceFileMetadataDamage(
        to mutation: inout SemanticManifestMutation
    ) {
        switch self {
        case .absentMain:
            mutation.replaceSourceFile(
                role: .main,
                disposition: .absent,
                byteCount: nil,
                sha256: nil
            )
        case .rebuiltWAL:
            mutation.replaceSourceFile(
                role: .wal,
                disposition: .rebuild,
                byteCount: 1,
                sha256: Self.validDigest
            )
        case .copiedSHM:
            mutation.replaceSourceFile(
                role: .shm,
                disposition: .copied,
                byteCount: 1,
                sha256: Self.validDigest
            )
        case .negativeMainSize:
            mutation.replaceSourceFile(
                role: .main,
                disposition: .copied,
                byteCount: -1,
                sha256: Self.validDigest
            )
        case .malformedMainDigest:
            mutation.replaceSourceFile(
                role: .main,
                disposition: .copied,
                byteCount: 1,
                sha256: "not-a-sha256"
            )
        case .copiedWALWithoutFingerprint:
            mutation.replaceSourceFile(
                role: .wal,
                disposition: .copied,
                byteCount: nil,
                sha256: nil
            )
        case .absentWALWithFingerprint:
            mutation.replaceSourceFile(
                role: .wal,
                disposition: .absent,
                byteCount: 1,
                sha256: Self.validDigest
            )
        case .rebuiltSHMWithoutFingerprint:
            mutation.replaceSourceFile(
                role: .shm,
                disposition: .rebuild,
                byteCount: nil,
                sha256: nil
            )
        default:
            break
        }
    }

    private func applySnapshotDamage(
        to mutation: inout SemanticManifestMutation
    ) {
        switch self {
        case .snapshotBeforeValidation:
            mutation.phase = .mainCopied
        case .missingValidatedSnapshot:
            mutation.snapshot = nil
        case .negativeSnapshotSize:
            mutation.makeSnapshotSizeNegative()
        case .malformedSnapshotDigest:
            mutation.malformSnapshotDigest()
        default:
            break
        }
    }

    private static let validDigest = String(repeating: "a", count: 64)
}

private struct SemanticManifestMutation {
    private let original: LocalCatalogMigrationManifest
    var origin: LocalCatalogMigrationManifest.Origin
    var sourcePath: String?
    var legacyName: String?
    var phase: LocalCatalogMigrationManifest.Phase
    var sourceFiles: [LocalCatalogMigrationManifest.SourceFile]
    var snapshot: LocalCatalogMigrationManifest.Snapshot?

    init(_ manifest: LocalCatalogMigrationManifest) {
        original = manifest
        origin = manifest.origin
        sourcePath = manifest.sourceStoreRelativePath
        legacyName = manifest.legacyDirectoryName
        phase = manifest.phase
        sourceFiles = manifest.sourceFiles
        snapshot = manifest.stagedSnapshot
    }

    mutating func adopt(
        phase: LocalCatalogMigrationManifest.Phase,
        clearsSnapshot: Bool
    ) {
        origin = .adoptedValidatedLocal
        sourcePath = nil
        legacyName = nil
        self.phase = phase
        sourceFiles = []
        if clearsSnapshot {
            snapshot = nil
        }
    }

    mutating func replaceSourceFile(
        role: LocalCatalogMigrationManifest.SourceFile.Role,
        disposition: LocalCatalogMigrationManifest.SourceFile.Disposition,
        byteCount: Int64?,
        sha256: String?
    ) {
        sourceFiles = replacingSourceFile(
            in: sourceFiles,
            role: role,
            disposition: disposition,
            byteCount: byteCount,
            sha256: sha256
        )
    }

    mutating func makeSnapshotSizeNegative() {
        guard let snapshot else {
            return
        }
        self.snapshot = LocalCatalogMigrationManifest.Snapshot(
            byteCount: -1,
            sha256: snapshot.sha256,
            quickCheck: snapshot.quickCheck
        )
    }

    mutating func malformSnapshotDigest() {
        guard let snapshot else {
            return
        }
        self.snapshot = LocalCatalogMigrationManifest.Snapshot(
            byteCount: snapshot.byteCount,
            sha256: "not-a-sha256",
            quickCheck: snapshot.quickCheck
        )
    }

    var result: LocalCatalogMigrationManifest {
        LocalCatalogMigrationManifest(
            schemaVersion: original.schemaVersion,
            operationID: original.operationID,
            libraryID: original.libraryID,
            origin: origin,
            sourceStoreRelativePath: sourcePath,
            stagingDirectoryName: original.stagingDirectoryName,
            legacyDirectoryName: legacyName,
            phase: phase,
            sourceFiles: sourceFiles,
            stagedSnapshot: snapshot
        )
    }
}

private func replacingSourceFile(
    in sourceFiles: [LocalCatalogMigrationManifest.SourceFile],
    role: LocalCatalogMigrationManifest.SourceFile.Role,
    disposition: LocalCatalogMigrationManifest.SourceFile.Disposition,
    byteCount: Int64?,
    sha256: String?
) -> [LocalCatalogMigrationManifest.SourceFile] {
    var sourceFiles = sourceFiles
    guard let index = sourceFiles.firstIndex(where: { $0.role == role }) else {
        return sourceFiles
    }
    sourceFiles[index] = LocalCatalogMigrationManifest.SourceFile(
        role: role,
        disposition: disposition,
        byteCount: byteCount,
        sha256: sha256
    )
    return sourceFiles
}

func expectInvalidManifest(
    _ operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected the semantic manifest validator to reject the state.")
    } catch let error as LocalCatalogMigrationError {
        guard case .invalidManifest = error else {
            Issue.record("Expected invalidManifest, got \(error).")
            return
        }
    } catch {
        Issue.record("Expected invalidManifest, got \(error).")
    }
}

func expectUnsafePath(
    _ operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected filesystem containment validation to reject the path.")
    } catch let error as LocalCatalogMigrationError {
        guard case .unsafePath = error else {
            Issue.record("Expected unsafePath, got \(error).")
            return
        }
    } catch {
        Issue.record("Expected unsafePath, got \(error).")
    }
}

func expectCatalogMigrationError(
    _ expectedCasePrefix: String,
    _ operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected catalog persistence validation to reject the state.")
    } catch let error as LocalCatalogMigrationError {
        #expect(String(describing: error).hasPrefix(expectedCasePrefix))
    } catch {
        Issue.record("Expected LocalCatalogMigrationError, got \(error).")
    }
}

final class OneShotFailureGate: @unchecked Sendable {
    private let lock = NSLock()
    private let target: LocalCatalogMigrationFailurePoint
    private var injected = false

    init(target: LocalCatalogMigrationFailurePoint) {
        self.target = target
    }

    var didInject: Bool {
        lock.withLock { injected }
    }

    func inject(_ point: LocalCatalogMigrationFailurePoint) throws {
        let shouldInject = lock.withLock {
            guard point == target, !injected else { return false }
            injected = true
            return true
        }
        if shouldInject {
            throw CatalogMigrationTestInterruption.injected
        }
    }
}

final class MigrationEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var events: [String] {
        lock.withLock { storage }
    }

    func append(_ event: String) {
        lock.withLock { storage.append(event) }
    }
}

final class FactoryOpenRace: @unchecked Sendable {
    let ownerOpened = DispatchSemaphore(value: 0)
    let releaseOwner = DispatchSemaphore(value: 0)
    let ownerFinished = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var storedOwnerFailure: String?
    private var competingOpen = false

    var ownerFailure: String? {
        lock.withLock { storedOwnerFailure }
    }

    var didEnterCompetingOpen: Bool {
        lock.withLock { competingOpen }
    }

    func recordOwnerFailure(_ error: any Error) {
        lock.withLock { storedOwnerFailure = error.localizedDescription }
    }

    func recordCompetingOpen() {
        lock.withLock { competingOpen = true }
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.withLock { storage }
    }

    func set() {
        lock.withLock { storage = true }
    }
}

final class AfterDirectorySyncFailureGate: @unchecked Sendable {
    private let lock = NSLock()
    private let targetPath: String
    private var matchesToSkip: Int
    private var armed = false
    private var injected = false

    init(target: URL, matchesToSkip: Int = 0) {
        targetPath = target.standardizedFileURL.path
        self.matchesToSkip = matchesToSkip
    }

    var didInject: Bool {
        lock.withLock { injected }
    }

    func arm() {
        lock.withLock { armed = true }
    }

    func injectIfArmed(for url: URL) throws {
        let shouldInject = lock.withLock {
            guard armed,
                  !injected,
                  url.standardizedFileURL.path == targetPath
            else {
                return false
            }
            if matchesToSkip > 0 {
                matchesToSkip -= 1
                return false
            }
            injected = true
            return true
        }
        if shouldInject {
            throw CatalogMigrationTestInterruption.injected
        }
    }
}

final class ExternalCatalogLockOwner: @unchecked Sendable {
    private var processID: pid_t

    init(processID: pid_t) {
        self.processID = processID
    }

    deinit {
        terminateAndWait()
    }

    var isRunning: Bool {
        processID > 0 && Darwin.kill(processID, 0) == 0
    }

    func terminateAndWait() {
        guard processID > 0 else {
            return
        }
        _ = Darwin.kill(processID, SIGKILL)
        var status: Int32 = 0
        while Darwin.waitpid(processID, &status, 0) == -1, errno == EINTR {}
        processID = 0
    }
}

func startExternalCatalogLockOwner(
    at lockURL: URL
) throws -> ExternalCatalogLockOwner {
    var readinessPipe: [Int32] = [-1, -1]
    guard Darwin.pipe(&readinessPipe) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let readDescriptor = readinessPipe[0]
    let writeDescriptor = readinessPipe[1]
    var child: pid_t = -1
    lockURL.path.withCString { lockPath in
        child = cadenceTestFork()
        guard child == 0 else {
            return
        }
        _ = Darwin.close(readDescriptor)
        let lockDescriptor = Darwin.open(
            lockPath,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard lockDescriptor >= 0 else {
            Darwin._exit(71)
        }
        var advisoryLock = flock()
        advisoryLock.l_type = Int16(F_WRLCK)
        advisoryLock.l_whence = Int16(SEEK_SET)
        guard Darwin.fcntl(lockDescriptor, F_SETLK, &advisoryLock) != -1 else {
            Darwin._exit(72)
        }
        var ready: UInt8 = 1
        guard Darwin.write(writeDescriptor, &ready, 1) == 1 else {
            Darwin._exit(73)
        }
        _ = Darwin.close(writeDescriptor)
        while true {
            _ = Darwin.pause()
        }
    }

    _ = Darwin.close(writeDescriptor)
    guard child > 0 else {
        _ = Darwin.close(readDescriptor)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    var ready: UInt8 = 0
    let bytesRead = Darwin.read(readDescriptor, &ready, 1)
    _ = Darwin.close(readDescriptor)
    guard bytesRead == 1, ready == 1 else {
        var status: Int32 = 0
        _ = Darwin.waitpid(child, &status, 0)
        throw NSError(
            domain: "CadenceCatalogLockTest",
            code: Int(status)
        )
    }
    return ExternalCatalogLockOwner(processID: child)
}

struct MigrationTreeSnapshot: Equatable {
    let directories: Set<String>
    let files: [String: Data]
}

func snapshotTree(at root: URL) throws -> MigrationTreeSnapshot {
    var directories: Set<String> = []
    var files: [String: Data] = [:]
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return MigrationTreeSnapshot(directories: [], files: [:])
    }
    let prefix = root.path + "/"
    for case let url as URL in enumerator {
        let relative = String(url.path.dropFirst(prefix.count))
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            directories.insert(relative)
        } else {
            files[relative] = try Data(contentsOf: url)
        }
    }
    return MigrationTreeSnapshot(directories: directories, files: files)
}

struct MigrationFixture: @unchecked Sendable {
    let root: URL
    let applicationSupportDirectory: URL
    let package: ManagedLibraryPackage
    let localCatalog: LocalLibraryCatalogLocation
    let identity: LibraryIdentity

    var catalogPointerURL: URL {
        package.metadataDirectoryURL.appending(
            path: "LocalCatalogPointer.json",
            directoryHint: .notDirectory
        )
    }

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Catalog-Migration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let applicationSupportDirectory = root.appending(
            path: "Application Support",
            directoryHint: .isDirectory
        )
        let package = ManagedLibraryPackage(
            location: ManagedLibraryLocation(
                musicDirectory: root.appending(
                    path: "Managed",
                    directoryHint: .isDirectory
                )
            )
        )
        try package.bootstrapForConfirmedImport()
        let identity = LibraryIdentity()
        try package.writeIdentity(identity)
        let localCatalog = LocalLibraryCatalogLocation(
            applicationSupportDirectory: applicationSupportDirectory,
            identity: identity
        )
        self.root = root
        self.applicationSupportDirectory = applicationSupportDirectory
        self.package = package
        self.localCatalog = localCatalog
        self.identity = identity
    }

    @MainActor
    func makeSourceCatalog(marker: String) throws -> ModelContainer {
        let container = try LibraryContainerFactory.persistent(package: package)
        let context = ModelContext(container)
        context.insert(TagRecord(displayPath: marker))
        try context.save()
        return container
    }

    func makeProbePackage(from storeURL: URL) throws -> ManagedLibraryPackage {
        let probe = ManagedLibraryPackage(
            location: ManagedLibraryLocation(
                musicDirectory: root.appending(
                    path: "Probe-\(UUID().uuidString)",
                    directoryHint: .isDirectory
                )
            )
        )
        try probe.bootstrapForConfirmedImport()
        try FileManager.default.copyItem(at: storeURL, to: probe.metadataStoreURL)
        return probe
    }

    func manifest() throws -> LocalCatalogMigrationManifest {
        try JSONDecoder().decode(
            LocalCatalogMigrationManifest.self,
            from: Data(contentsOf: localCatalog.migrationManifestURL)
        )
    }

    func writeManifest(_ manifest: LocalCatalogMigrationManifest) throws {
        try JSONEncoder().encode(manifest).write(
            to: localCatalog.migrationManifestURL,
            options: .atomic
        )
    }

    func writeSearchArtifacts() throws {
        for suffix in ["", "-wal", "-shm"] {
            try Data("search\(suffix)".utf8).write(
                to: URL(filePath: package.lyricsSearchDatabaseURL.path + suffix)
            )
        }
    }

    func catalogPointer() throws -> CatalogPointerFixture {
        try JSONDecoder().decode(
            CatalogPointerFixture.self,
            from: Data(contentsOf: catalogPointerURL)
        )
    }

    func writeManagedMedia() throws -> (url: URL, bytes: Data) {
        let url = package.mediaDirectoryURL.appending(
            path: "\(UUID().uuidString).mp3",
            directoryHint: .notDirectory
        )
        let bytes = Data("retained-managed-media".utf8)
        try bytes.write(to: url)
        return (url, bytes)
    }

    func writeStaleLocalMetadata() throws -> Data {
        let bytes = Data("stale-local-catalog".utf8)
        try FileManager.default.createDirectory(
            at: localCatalog.metadataDirectoryURL,
            withIntermediateDirectories: true
        )
        try bytes.write(to: localCatalog.storeURL)
        return bytes
    }

    func operationDirectories() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: localCatalog.rootURL,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasSuffix(".staging")
        }
    }

    func allDescendants() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
    }

    func treeSnapshot() throws -> MigrationTreeSnapshot {
        var directories: Set<String> = []
        var files: [String: Data] = [:]
        let prefix = root.path + "/"
        for url in try allDescendants() {
            let relative = String(url.path.dropFirst(prefix.count))
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                directories.insert(relative)
            } else {
                files[relative] = try Data(contentsOf: url)
            }
        }
        return MigrationTreeSnapshot(directories: directories, files: files)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
