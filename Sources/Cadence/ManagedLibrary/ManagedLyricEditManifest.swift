import Foundation

enum ManagedLyricEditManifestError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case invalidTargetPath(String)
    case invalidHash(String)
    case invalidState

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Lyrics edit manifest version \(version) is not supported."
        case let .invalidTargetPath(path):
            "Lyrics edit manifest has an invalid target: \(path)."
        case let .invalidHash(hash):
            "Lyrics edit manifest has an invalid SHA-256 hash: \(hash)."
        case .invalidState:
            "Lyrics edit manifest has inconsistent content."
        }
    }
}

struct ManagedLyricEditManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1

    enum State: String, Codable, Sendable {
        case prepared
        case fileInstalled
        case metadataCommitted
    }

    let version: Int
    let operationID: UUID
    let trackID: UUID
    let createdAt: Date
    let targetRelativePath: String
    let previousContentHash: String?
    let newContentHash: String?
    let newTimingStatusRawValue: String?
    let modifiedAt: Date
    let state: State

    init(
        version: Int = currentVersion,
        operationID: UUID,
        trackID: UUID,
        createdAt: Date = .now,
        targetRelativePath: String,
        previousContentHash: String?,
        newContentHash: String?,
        newTimingStatus: LyricTimingStatus?,
        modifiedAt: Date = .now,
        state: State
    ) {
        self.version = version
        self.operationID = operationID
        self.trackID = trackID
        self.createdAt = createdAt
        self.targetRelativePath = targetRelativePath
        self.previousContentHash = previousContentHash
        self.newContentHash = newContentHash
        newTimingStatusRawValue = newTimingStatus?.storageRawValue
        self.modifiedAt = modifiedAt
        self.state = state
    }

    var newTimingStatus: LyricTimingStatus? {
        newTimingStatusRawValue.flatMap(
            LyricTimingStatus.init(storageRawValue:)
        )
    }

    var mutation: ManagedLyricMutation {
        if let newContentHash, let newTimingStatus {
            return .upsert(
                relativePath: targetRelativePath,
                contentHash: newContentHash,
                timingStatus: newTimingStatus,
                modifiedAt: modifiedAt
            )
        }
        return .remove
    }

    func advancing(
        to state: State
    ) -> ManagedLyricEditManifest {
        ManagedLyricEditManifest(
            version: version,
            operationID: operationID,
            trackID: trackID,
            createdAt: createdAt,
            targetRelativePath: targetRelativePath,
            previousContentHash: previousContentHash,
            newContentHash: newContentHash,
            newTimingStatus: newTimingStatus,
            modifiedAt: modifiedAt,
            state: state
        )
    }

    func validated() throws -> ManagedLyricEditManifest {
        guard version == Self.currentVersion else {
            throw ManagedLyricEditManifestError.unsupportedVersion(version)
        }
        let expectedPath = "Lyrics/\(trackID.uuidString).lrc"
        guard targetRelativePath == expectedPath else {
            throw ManagedLyricEditManifestError.invalidTargetPath(
                targetRelativePath
            )
        }
        if let previousContentHash {
            try validate(hash: previousContentHash)
        }
        if let newContentHash {
            try validate(hash: newContentHash)
        }
        guard
            (newContentHash == nil) == (newTimingStatusRawValue == nil),
            newTimingStatusRawValue == nil || newTimingStatus != nil
        else {
            throw ManagedLyricEditManifestError.invalidState
        }
        return self
    }

    private func validate(
        hash: String
    ) throws {
        let isHex = hash.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdef").contains($0)
        }
        guard hash.count == 64, isHex else {
            throw ManagedLyricEditManifestError.invalidHash(hash)
        }
    }
}

struct ManagedLyricEditManifestStore: Sendable {
    static let manifestFilename = "Manifest.json"
    static let stagedFilename = "new.lrc"
    static let previousFilename = "previous.lrc"

    let package: ManagedLibraryPackage

    var rootURL: URL {
        package.stagingDirectoryURL.appending(
            path: "LyricsEdits",
            directoryHint: .isDirectory
        )
    }

    var quarantineRootURL: URL {
        package.stagingDirectoryURL.appending(
            path: "LyricsEditsQuarantine",
            directoryHint: .isDirectory
        )
    }

    func save(
        _ uncheckedManifest: ManagedLyricEditManifest
    ) throws {
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

    func loadRecoverable() throws -> [ManagedLyricEditManifest] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }
        let directories = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var manifests: [ManagedLyricEditManifest] = []
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
                try quarantine(
                    directory: directory,
                    operationID: operationID
                )
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
                        ManagedLyricEditManifest.self,
                        from: data
                    ).validated()
                )
            } catch {
                try quarantine(
                    directory: directory,
                    operationID: operationID
                )
            }
        }
        return manifests.sorted { $0.createdAt < $1.createdAt }
    }

    func operationURL(
        _ operationID: UUID
    ) -> URL {
        rootURL.appending(
            path: operationID.uuidString,
            directoryHint: .isDirectory
        )
    }

    func manifestURL(
        _ operationID: UUID
    ) -> URL {
        operationURL(operationID).appending(
            path: Self.manifestFilename,
            directoryHint: .notDirectory
        )
    }

    func stagedURL(
        _ operationID: UUID
    ) -> URL {
        operationURL(operationID).appending(
            path: Self.stagedFilename,
            directoryHint: .notDirectory
        )
    }

    func previousURL(
        _ operationID: UUID
    ) -> URL {
        operationURL(operationID).appending(
            path: Self.previousFilename,
            directoryHint: .notDirectory
        )
    }

    func remove(
        _ operationID: UUID
    ) throws {
        let url = operationURL(operationID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    func quarantine(
        _ operationID: UUID
    ) throws {
        let directory = operationURL(operationID)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try quarantine(
            directory: directory,
            operationID: operationID
        )
    }

    private func quarantine(
        directory: URL,
        operationID: UUID
    ) throws {
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
            throw ManagedLyricEditManifestError.invalidState
        }
        try fileManager.moveItem(at: directory, to: destination)
    }
}
