import Foundation

struct ManagedTrackMetadataEditManifest: Codable, Sendable {
    static let currentVersion = 1

    enum State: String, Codable, Sendable {
        case prepared
        case fileInstalled
        case metadataCommitted
    }

    let version: Int
    let operationID: UUID
    let trackID: UUID
    let relativeMediaPath: String
    let originalHash: String
    let editedHash: String?
    let metadata: ManagedImportManifest.Metadata?
    let sourceMetadata: Data?
    let state: State

    init(
        version: Int = currentVersion,
        operationID: UUID,
        trackID: UUID,
        relativeMediaPath: String,
        originalHash: String,
        editedHash: String? = nil,
        metadata: ManagedImportManifest.Metadata? = nil,
        sourceMetadata: Data? = nil,
        state: State
    ) {
        self.version = version
        self.operationID = operationID
        self.trackID = trackID
        self.relativeMediaPath = relativeMediaPath
        self.originalHash = originalHash
        self.editedHash = editedHash
        self.metadata = metadata
        self.sourceMetadata = sourceMetadata
        self.state = state
    }

    func advancing(
        to state: State,
        repair: ManagedMetadataRepair? = nil
    ) -> Self {
        Self(
            operationID: operationID,
            trackID: trackID,
            relativeMediaPath: relativeMediaPath,
            originalHash: originalHash,
            editedHash: repair?.contentHash ?? editedHash,
            metadata: repair?.metadata ?? metadata,
            sourceMetadata: repair?.sourceMetadata ?? sourceMetadata,
            state: state
        )
    }

    var repair: ManagedMetadataRepair? {
        guard let metadata, let sourceMetadata, let editedHash else {
            return nil
        }
        return ManagedMetadataRepair(
            trackID: trackID,
            metadata: metadata,
            sourceMetadata: sourceMetadata,
            contentHash: editedHash
        )
    }
}

struct ManagedTrackMetadataEditManifestStore: Sendable {
    let package: ManagedLibraryPackage

    var rootURL: URL {
        package.stagingDirectoryURL.appending(
            path: "MetadataEdits",
            directoryHint: .isDirectory
        )
    }

    func save(_ manifest: ManagedTrackMetadataEditManifest) throws {
        let directory = operationURL(manifest.operationID)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: manifestURL(manifest.operationID),
            options: .atomic
        )
    }

    func loadRecoverable() throws -> [ManagedTrackMetadataEditManifest] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { directory in
            guard UUID(uuidString: directory.lastPathComponent) != nil else {
                return nil
            }
            return try JSONDecoder().decode(
                ManagedTrackMetadataEditManifest.self,
                from: Data(contentsOf: directory.appending(path: "Manifest.json"))
            )
        }
    }

    func operationURL(_ operationID: UUID) -> URL {
        rootURL.appending(
            path: operationID.uuidString,
            directoryHint: .isDirectory
        )
    }

    func manifestURL(_ operationID: UUID) -> URL {
        operationURL(operationID).appending(
            path: "Manifest.json",
            directoryHint: .notDirectory
        )
    }

    func backupURL(_ manifest: ManagedTrackMetadataEditManifest) -> URL {
        operationURL(manifest.operationID).appending(
            path: "Original.\((manifest.relativeMediaPath as NSString).pathExtension)",
            directoryHint: .notDirectory
        )
    }

    func remove(_ operationID: UUID) throws {
        let directory = operationURL(operationID)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
