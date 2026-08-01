import Foundation

enum ManagedArtworkEditManifestError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case invalidArtwork
    case invalidPath(String)
    case invalidHash(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Artwork edit manifest version \(version) is not supported."
        case .invalidArtwork:
            "Artwork edit manifest has inconsistent artwork metadata."
        case let .invalidPath(path):
            "Artwork edit manifest has an invalid path: \(path)."
        case let .invalidHash(hash):
            "Artwork edit manifest has an invalid SHA-256 hash: \(hash)."
        }
    }
}

struct ManagedArtworkDescriptor: Codable, Equatable, Sendable {
    let id: UUID
    let ownerKind: ArtworkOwnerKind
    let ownerID: UUID
    let relativeOriginalPath: String
    let relativeThumbnailPath: String?
    let format: String
    let pixelWidth: Int
    let pixelHeight: Int
    let cropScale: Double
    let normalizedOffsetX: Double
    let normalizedOffsetY: Double
    let contentHash: String
    let revision: Int

    var relativePaths: [String] {
        [relativeOriginalPath, relativeThumbnailPath].compactMap(\.self)
    }

    func validated() throws -> ManagedArtworkDescriptor {
        guard pixelWidth > 0, pixelHeight > 0, revision >= 0 else {
            throw ManagedArtworkEditManifestError.invalidArtwork
        }
        guard cropScale >= 1, cropScale <= 4 else {
            throw ManagedArtworkEditManifestError.invalidArtwork
        }
        try validate(hash: contentHash)
        for path in relativePaths {
            try validate(relativePath: path)
        }
        return self
    }

    private func validate(relativePath: String) throws {
        let isArtworkPath = relativePath.hasPrefix("Artwork/Original/")
            || relativePath.hasPrefix("Artwork/Thumbnails/")
        guard
            isArtworkPath,
            !relativePath.hasPrefix("/"),
            !relativePath.split(separator: "/").contains("..")
        else {
            throw ManagedArtworkEditManifestError.invalidPath(relativePath)
        }
    }

    private func validate(hash: String) throws {
        let hexadecimal = CharacterSet(
            charactersIn: "0123456789abcdef"
        )
        let isHex = hash.unicodeScalars.allSatisfy {
            hexadecimal.contains($0)
        }
        guard hash.count == 64, isHex else {
            throw ManagedArtworkEditManifestError.invalidHash(hash)
        }
    }
}

struct ManagedArtworkEditManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1

    enum MutationKind: String, Codable, Sendable {
        case set
        case remove
    }

    enum State: String, Codable, Sendable {
        case prepared
        case fileInstalled
        case metadataCommitted
    }

    let version: Int
    let operationID: UUID
    let createdAt: Date
    let ownerKind: ArtworkOwnerKind
    let ownerID: UUID
    let mutationKind: MutationKind
    let previousArtwork: ManagedArtworkDescriptor?
    let newArtwork: ManagedArtworkDescriptor?
    let state: State

    init(
        version: Int = currentVersion,
        operationID: UUID,
        createdAt: Date = .now,
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID,
        mutationKind: MutationKind,
        previousArtwork: ManagedArtworkDescriptor?,
        newArtwork: ManagedArtworkDescriptor?,
        state: State
    ) {
        self.version = version
        self.operationID = operationID
        self.createdAt = createdAt
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.mutationKind = mutationKind
        self.previousArtwork = previousArtwork
        self.newArtwork = newArtwork
        self.state = state
    }

    func advancing(to state: State) -> ManagedArtworkEditManifest {
        ManagedArtworkEditManifest(
            version: version,
            operationID: operationID,
            createdAt: createdAt,
            ownerKind: ownerKind,
            ownerID: ownerID,
            mutationKind: mutationKind,
            previousArtwork: previousArtwork,
            newArtwork: newArtwork,
            state: state
        )
    }

    func validated() throws -> ManagedArtworkEditManifest {
        guard version == Self.currentVersion else {
            throw ManagedArtworkEditManifestError.unsupportedVersion(version)
        }
        guard
            previousArtwork?.ownerKind == nil
            || previousArtwork?.ownerKind == ownerKind,
            previousArtwork?.ownerID == nil
            || previousArtwork?.ownerID == ownerID,
            newArtwork?.ownerKind == nil || newArtwork?.ownerKind == ownerKind,
            newArtwork?.ownerID == nil || newArtwork?.ownerID == ownerID
        else {
            throw ManagedArtworkEditManifestError.invalidArtwork
        }
        switch mutationKind {
        case .set:
            guard let newArtwork else {
                throw ManagedArtworkEditManifestError.invalidArtwork
            }
            _ = try newArtwork.validated()
            let expectedPath = "Artwork/Original/\(newArtwork.id.uuidString)."
                + newArtwork.format
            guard newArtwork.relativeOriginalPath == expectedPath else {
                throw ManagedArtworkEditManifestError.invalidPath(
                    newArtwork.relativeOriginalPath
                )
            }
        case .remove:
            guard newArtwork == nil else {
                throw ManagedArtworkEditManifestError.invalidArtwork
            }
        }
        if let previousArtwork {
            _ = try previousArtwork.validated()
        }
        return self
    }
}

struct ManagedArtworkEditManifestStore: Sendable {
    static let manifestFilename = "Manifest.json"
    static let stagedFilename = "new-artwork"

    let package: ManagedLibraryPackage

    var rootURL: URL {
        package.stagingDirectoryURL.appending(
            path: "ArtworkEdits",
            directoryHint: .isDirectory
        )
    }

    var quarantineRootURL: URL {
        package.stagingDirectoryURL.appending(
            path: "ArtworkEditsQuarantine",
            directoryHint: .isDirectory
        )
    }

    func save(_ uncheckedManifest: ManagedArtworkEditManifest) throws {
        let manifest = try uncheckedManifest.validated()
        let directory = operationURL(manifest.operationID)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: manifestURL(manifest.operationID),
            options: .atomic
        )
    }

    func loadRecoverable() throws -> [ManagedArtworkEditManifest] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }
        let directories = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles]
        )
        var manifests: [ManagedArtworkEditManifest] = []
        for directory in directories {
            guard let operationID = UUID(
                uuidString: directory.lastPathComponent
            ) else {
                continue
            }
            let values = try directory.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                try quarantine(directory: directory, operationID: operationID)
                continue
            }
            guard values.isDirectory == true else {
                continue
            }
            do {
                let data = try Data(contentsOf: manifestURL(operationID))
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                try manifests.append(
                    decoder.decode(
                        ManagedArtworkEditManifest.self,
                        from: data
                    ).validated()
                )
            } catch {
                try quarantine(directory: directory, operationID: operationID)
            }
        }
        return manifests.sorted { $0.createdAt < $1.createdAt }
    }

    func operationURL(_ operationID: UUID) -> URL {
        rootURL.appending(
            path: operationID.uuidString,
            directoryHint: .isDirectory
        )
    }

    func manifestURL(_ operationID: UUID) -> URL {
        operationURL(operationID).appending(
            path: Self.manifestFilename,
            directoryHint: .notDirectory
        )
    }

    func stagedURL(_ operationID: UUID) -> URL {
        operationURL(operationID).appending(
            path: Self.stagedFilename,
            directoryHint: .notDirectory
        )
    }

    func remove(_ operationID: UUID) throws {
        let directory = operationURL(operationID)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    func quarantine(_ operationID: UUID) throws {
        let directory = operationURL(operationID)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try quarantine(directory: directory, operationID: operationID)
    }

    private func quarantine(directory: URL, operationID: UUID) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: quarantineRootURL,
            withIntermediateDirectories: true
        )
        let destination = quarantineRootURL.appending(
            path: operationID.uuidString,
            directoryHint: .isDirectory
        )
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ManagedArtworkEditManifestError.invalidArtwork
        }
        try fileManager.moveItem(at: directory, to: destination)
    }
}
