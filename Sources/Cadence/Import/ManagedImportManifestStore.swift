import Foundation

struct ManagedImportManifestStore: Sendable {
    static let filename = "Manifest.json"

    let package: ManagedLibraryPackage

    func save(
        _ uncheckedManifest: ManagedImportManifest
    ) throws {
        let manifest = try uncheckedManifest.validated()
        let directory = package.stagingURL(importID: manifest.importID)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL(importID: manifest.importID), options: .atomic)
    }

    func load(
        importID: UUID
    ) throws -> ManagedImportManifest {
        let data = try Data(contentsOf: manifestURL(importID: importID))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(
            ManagedImportManifest.self,
            from: data
        ).validated()
    }

    func loadRecoverableManifests() throws -> [ManagedImportManifest] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: package.stagingDirectoryURL.path) else {
            return []
        }
        let directories = try fileManager.contentsOfDirectory(
            at: package.stagingDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try directories.compactMap { directory in
            guard
                try (directory.resourceValues(
                    forKeys: [.isDirectoryKey]
                ).isDirectory) == true,
                UUID(uuidString: directory.lastPathComponent) != nil
            else {
                return nil
            }
            let manifestURL = directory.appending(
                path: Self.filename,
                directoryHint: .notDirectory
            )
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                return nil
            }
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return try decoder.decode(
                ManagedImportManifest.self,
                from: data
            ).validated()
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    func remove(
        importID: UUID
    ) throws {
        let directory = package.stagingURL(importID: importID)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    func manifestURL(
        importID: UUID
    ) -> URL {
        package.stagingURL(importID: importID).appending(
            path: Self.filename,
            directoryHint: .notDirectory
        )
    }

    func stagedURL(
        importID: UUID,
        relativePath: String
    ) throws -> URL {
        _ = try package.location.resolve(relativePath: relativePath)
        return package.stagingURL(importID: importID).appending(
            path: relativePath,
            directoryHint: .notDirectory
        )
    }
}
