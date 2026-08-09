import Foundation
import SwiftData

enum LibraryRelocationError: Error, Equatable, LocalizedError, Sendable {
    case sourceUnavailable(URL)
    case sameLocation
    case destinationConflict(URL)
    case verificationFailed(String)
    case invalidDestination(String)

    var errorDescription: String? {
        switch self {
        case let .sourceUnavailable(url):
            "The active library is unavailable at \(url.path)."
        case .sameLocation:
            "The library is already stored in this folder."
        case let .destinationConflict(url):
            "A Cadence.library package already exists at \(url.path)."
        case let .verificationFailed(path):
            "The copied file failed verification: \(path)."
        case let .invalidDestination(message):
            "The copied library could not be opened: \(message)"
        }
    }
}

struct PreparedLibraryRelocation: Sendable {
    let source: ManagedLibraryLocation
    let destination: ManagedLibraryLocation
    let manifestURL: URL
    let sourceManifestURL: URL
    let manifest: LibraryRelocationManifest
    let repository: LibraryRepository
}

private struct RelocationContext: Sendable {
    let sourcePackage: ManagedLibraryPackage
    let destination: ManagedLibraryLocation
    let destinationPackage: ManagedLibraryPackage
    let stagingURL: URL
    let manifestURL: URL
    let sourceManifestURL: URL
    let manifest: LibraryRelocationManifest

    var manifestURLs: [URL] {
        [manifestURL, sourceManifestURL]
    }

    init(
        sourcePackage: ManagedLibraryPackage,
        destination: ManagedLibraryLocation,
        destinationParent: URL
    ) throws {
        self.sourcePackage = sourcePackage
        self.destination = destination
        destinationPackage = ManagedLibraryPackage(location: destination)
        let operationID = UUID()
        stagingURL = destinationParent.appending(
            path: ".Cadence-relocation-\(operationID.uuidString)",
            directoryHint: .isDirectory
        )
        manifestURL = destinationParent.appending(
            path: ".Cadence-relocation-\(operationID.uuidString).json",
            directoryHint: .notDirectory
        )
        sourceManifestURL = sourcePackage.stagingDirectoryURL
            .appending(path: "Relocations", directoryHint: .isDirectory)
            .appending(
                path: "\(operationID.uuidString).json",
                directoryHint: .notDirectory
            )
        manifest = try LibraryRelocationManifest(
            operationID: operationID,
            libraryIdentity: sourcePackage.readOrCreateIdentity(),
            sourcePackagePath: sourcePackage.packageURL.path,
            destinationPackagePath: destinationPackage.packageURL.path,
            phase: .preflight,
            files: []
        )
    }
}

actor LibraryRelocator {
    typealias Validator = @Sendable (
        ManagedLibraryPackage
    ) throws -> ModelContainer

    private let fileManager: FileManager
    private let hasher: ContentHasher
    private let validate: Validator

    init(
        fileManager: FileManager = .default,
        hasher: ContentHasher = ContentHasher(),
        validate: @escaping Validator = LibraryContainerFactory.persistent
    ) {
        self.fileManager = fileManager
        self.hasher = hasher
        self.validate = validate
    }

    func prepare(
        source: ManagedLibraryLocation,
        destinationParent: URL,
        progress: @escaping @Sendable (LibraryRelocationProgress) async -> Void = { _ in }
    ) async throws -> PreparedLibraryRelocation {
        let context = try makeContext(
            source: source,
            destinationParent: destinationParent
        )
        var manifest = context.manifest
        try persist(manifest, at: context.manifestURL)
        await progress(.init(phase: .preflight, completedCount: 0, totalCount: 0))

        do {
            return try await performRelocation(
                source: source,
                context: context,
                manifest: &manifest,
                progress: progress
            )
        } catch {
            if fileManager.fileExists(atPath: context.stagingURL.path) {
                try? fileManager.removeItem(at: context.stagingURL)
            }
            throw error
        }
    }

    private func performRelocation(
        source: ManagedLibraryLocation,
        context: RelocationContext,
        manifest: inout LibraryRelocationManifest,
        progress: @escaping @Sendable (LibraryRelocationProgress) async -> Void
    ) async throws -> PreparedLibraryRelocation {
        let sourceFiles = try regularFiles(in: context.sourcePackage.packageURL)
        manifest.files = try await describe(
            sourceFiles,
            root: context.sourcePackage.packageURL
        )
        manifest.phase = .copying
        try persist(manifest, at: context.manifestURLs)
        try await copyFiles(manifest.files, context: context, progress: progress)

        manifest.phase = .verifying
        try persist(manifest, at: context.manifestURLs)
        try await verifyFiles(
            manifest.files,
            stagingURL: context.stagingURL,
            progress: progress
        )

        try finalize(context: context)
        manifest.phase = .finalized
        try persist(manifest, at: context.manifestURLs)
        await progress(.init(phase: .finalized, completedCount: 0, totalCount: 0))

        let repository = try validatedRepository(package: context.destinationPackage)
        manifest.phase = .destinationValidated
        try persist(manifest, at: context.manifestURLs)
        await progress(.init(phase: .destinationValidated, completedCount: 0, totalCount: 0))
        return PreparedLibraryRelocation(
            source: source,
            destination: context.destination,
            manifestURL: context.manifestURL,
            sourceManifestURL: context.sourceManifestURL,
            manifest: manifest,
            repository: repository
        )
    }

    private func makeContext(
        source: ManagedLibraryLocation,
        destinationParent: URL
    ) throws -> RelocationContext {
        let sourcePackage = ManagedLibraryPackage(location: source)
        let destination = ManagedLibraryLocation(musicDirectory: destinationParent)
        let destinationPackage = ManagedLibraryPackage(location: destination)
        guard source.packageURL != destination.packageURL else {
            throw LibraryRelocationError.sameLocation
        }
        guard fileManager.fileExists(atPath: sourcePackage.packageURL.path) else {
            throw LibraryRelocationError.sourceUnavailable(sourcePackage.packageURL)
        }
        guard !fileManager.fileExists(atPath: destinationPackage.packageURL.path) else {
            throw LibraryRelocationError.destinationConflict(destinationPackage.packageURL)
        }
        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        return try RelocationContext(
            sourcePackage: sourcePackage,
            destination: destination,
            destinationParent: destinationParent
        )
    }

    private func copyFiles(
        _ files: [RelocationFile],
        context: RelocationContext,
        progress: @escaping @Sendable (LibraryRelocationProgress) async -> Void
    ) async throws {
        try fileManager.createDirectory(
            at: context.stagingURL,
            withIntermediateDirectories: true
        )
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let sourceURL = context.sourcePackage.packageURL.appending(path: file.relativePath)
            let targetURL = context.stagingURL.appending(path: file.relativePath)
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: targetURL)
            await progress(
                .init(phase: .copying, completedCount: index + 1, totalCount: files.count)
            )
        }
    }

    private func verifyFiles(
        _ files: [RelocationFile],
        stagingURL: URL,
        progress: @escaping @Sendable (LibraryRelocationProgress) async -> Void
    ) async throws {
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let copiedURL = stagingURL.appending(path: file.relativePath)
            let digest = try await hasher.sha256(of: copiedURL)
            guard digest == file.sha256 else {
                throw LibraryRelocationError.verificationFailed(file.relativePath)
            }
            await progress(
                .init(phase: .verifying, completedCount: index + 1, totalCount: files.count)
            )
        }
    }

    private func finalize(
        context: RelocationContext
    ) throws {
        try fileManager.moveItem(
            at: context.stagingURL,
            to: context.destinationPackage.packageURL
        )
    }

    private func validatedRepository(
        package: ManagedLibraryPackage
    ) throws -> LibraryRepository {
        do {
            try package.bootstrapForConfirmedImport()
            return try LibraryRepository(
                modelContainer: validate(package)
            )
        } catch {
            throw LibraryRelocationError.invalidDestination(
                error.localizedDescription
            )
        }
    }

    func finishSwitch(
        _ prepared: PreparedLibraryRelocation,
        progress: @escaping @Sendable (LibraryRelocationProgress) async -> Void = { _ in }
    ) async -> Bool {
        var manifest = prepared.manifest
        manifest.phase = .switched
        try? persist(
            manifest,
            at: [prepared.manifestURL, prepared.sourceManifestURL]
        )
        await progress(.init(phase: .switched, completedCount: 0, totalCount: 0))

        manifest.phase = .sourceCleanup
        try? persist(
            manifest,
            at: [prepared.manifestURL, prepared.sourceManifestURL]
        )
        await progress(.init(phase: .sourceCleanup, completedCount: 0, totalCount: 0))
        do {
            var trashedURL: NSURL?
            try fileManager.trashItem(
                at: prepared.source.packageURL,
                resultingItemURL: &trashedURL
            )
            manifest.phase = .complete
            try persist(manifest, at: prepared.manifestURL)
            try? fileManager.removeItem(at: prepared.manifestURL)
            try? fileManager.removeItem(at: prepared.sourceManifestURL)
            await progress(.init(phase: .complete, completedCount: 0, totalCount: 0))
            return true
        } catch {
            return false
        }
    }
}

private extension LibraryRelocator {
    func regularFiles(
        in root: URL
    ) throws -> [URL] {
        let derivedSearchPath = root
            .appending(path: "Metadata/Search.sqlite")
            .standardizedFileURL.path
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return try enumerator.compactMap { element in
            guard let url = element as? URL else { return nil }
            guard !url.standardizedFileURL.path.hasPrefix(derivedSearchPath) else {
                return nil
            }
            return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                ? url
                : nil
        }.sorted { $0.path < $1.path }
    }

    func describe(
        _ files: [URL],
        root: URL
    ) async throws -> [RelocationFile] {
        var result: [RelocationFile] = []
        let rootComponents = root.resolvingSymlinksInPath().pathComponents
        for file in files {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            let fileComponents = file.resolvingSymlinksInPath().pathComponents
            guard fileComponents.starts(with: rootComponents) else {
                throw LibraryRelocationError.verificationFailed(file.path)
            }
            let relativePath = fileComponents
                .dropFirst(rootComponents.count)
                .joined(separator: "/")
            try await result.append(
                RelocationFile(
                    relativePath: relativePath,
                    byteCount: Int64(values.fileSize ?? 0),
                    sha256: hasher.sha256(of: file)
                )
            )
        }
        return result
    }

    func persist(
        _ manifest: LibraryRelocationManifest,
        at url: URL
    ) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    func persist(
        _ manifest: LibraryRelocationManifest,
        at urls: [URL]
    ) throws {
        for url in urls {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try persist(manifest, at: url)
        }
    }
}
