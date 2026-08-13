import Foundation

struct ManagedTrashManifestStore {
    let location: ManagedLibraryLocation

    func write(_ manifest: ManagedTrashManifest) throws {
        let url = manifestURL(for: manifest.operationID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    func read(operationID: UUID) throws -> ManagedTrashManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            ManagedTrashManifest.self,
            from: Data(contentsOf: manifestURL(for: operationID))
        )
        guard
            (2 ... ManagedTrashManifest.currentVersion).contains(
                manifest.version
            ),
            manifest.operationID == operationID
        else {
            throw LibraryTrashError.invalidManifest
        }
        return manifest
    }

    func manifestURL(for operationID: UUID) -> URL {
        ManagedLibraryPackage(location: location)
            .trashDirectoryURL
            .appending(path: operationID.uuidString, directoryHint: .isDirectory)
            .appending(path: "manifest.json", directoryHint: .notDirectory)
    }

    func operationIDs() throws -> [UUID] {
        let trashURL = ManagedLibraryPackage(location: location)
            .trashDirectoryURL
        guard FileManager.default.fileExists(atPath: trashURL.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).map { url in
            guard
                try url.resourceValues(forKeys: [.isDirectoryKey])
                .isDirectory == true,
                let operationID = UUID(uuidString: url.lastPathComponent)
            else {
                throw LibraryTrashError.invalidManifest
            }
            return operationID
        }
    }
}
