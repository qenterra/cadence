import Foundation

actor ManagedLyricsService {
    private let package: ManagedLibraryPackage
    private let repository: LibraryRepository
    private let manifestStore: ManagedLyricEditManifestStore
    private let hasher: ContentHasher
    private let fileManager: FileManager

    init(
        package: ManagedLibraryPackage,
        repository: LibraryRepository,
        hasher: ContentHasher = ContentHasher(),
        fileManager: FileManager = .default
    ) {
        self.package = package
        self.repository = repository
        manifestStore = ManagedLyricEditManifestStore(package: package)
        self.hasher = hasher
        self.fileManager = fileManager
    }

    func load(
        trackID: UUID
    ) async throws -> LyricDocument? {
        let result = try await loadResult(trackID: trackID)
        return result.document
    }

    func loadResult(
        trackID: UUID
    ) async throws -> ManagedLyricsLoadResult {
        let metadata = try await repository.lyricMetadata(
            trackID: trackID
        )
        let relativePath = metadata?.relativePath
            ?? "Lyrics/\(trackID.uuidString).lrc"
        let url = try package.location.resolve(
            relativePath: relativePath,
            directoryHint: .notDirectory
        )
        guard fileManager.fileExists(atPath: url.path) else {
            if metadata == nil {
                return ManagedLyricsLoadResult(
                    document: nil,
                    didRepairMetadata: false
                )
            }
            throw ManagedLyricsServiceError.unreadableManagedLyrics
        }
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ManagedLyricsServiceError.unreadableManagedLyrics
        }
        let actualHash = try await hasher.sha256(of: url)
        if let metadata, actualHash != metadata.contentHash {
            throw ManagedLyricsServiceError.contentHashMismatch
        }
        let document = try LineLevelLRC.parse(source, trackID: trackID)
        let didRepairMetadata = metadata == nil
        if didRepairMetadata {
            try await repository.applyLyricMutation(
                trackID: trackID,
                mutation: .upsert(
                    relativePath: relativePath,
                    contentHash: actualHash,
                    timingStatus: document.timingStatus,
                    modifiedAt: .now
                )
            )
        }
        return ManagedLyricsLoadResult(
            document: document,
            didRepairMetadata: didRepairMetadata
        )
    }

    @discardableResult
    func save(
        _ document: LyricDocument
    ) async throws -> ManagedLyricsSaveResult {
        guard case let .managed(trackID) = document.trackID else {
            throw ManagedLyricsServiceError.wrongTrackIdentity
        }
        let recovery = try await recover()
        do {
            let manifest = try await prepareOperation(
                document: document,
                trackID: trackID
            )
            let installed = try installOperation(manifest)
            try await commitOperation(installed)
            return ManagedLyricsSaveResult(
                recovery: recovery,
                savedTrackID: trackID
            )
        } catch {
            throw carryingRecovery(recovery, after: error)
        }
    }

    func recover() async throws -> ManagedLyricsRecoveryResult {
        let manifests = try manifestStore.loadRecoverable()
        guard !manifests.isEmpty else {
            return .empty
        }

        var recovered: [UUID] = []
        var rolledBack: [UUID] = []
        var affectedTrackIDs: [UUID] = []
        var affectedTrackIDSet: Set<UUID> = []
        for manifest in manifests {
            do {
                switch manifest.state {
                case .prepared:
                    try rollbackFile(for: manifest)
                    try manifestStore.remove(manifest.operationID)
                    rolledBack.append(manifest.operationID)
                case .fileInstalled:
                    try await verifyInstalledFile(for: manifest)
                    try await repository.applyLyricMutation(
                        trackID: manifest.trackID,
                        mutation: manifest.mutation
                    )
                    let committed = manifest.advancing(
                        to: .metadataCommitted
                    )
                    try manifestStore.save(committed)
                    try manifestStore.remove(manifest.operationID)
                    recovered.append(manifest.operationID)
                case .metadataCommitted:
                    try await verifyInstalledFile(for: manifest)
                    try manifestStore.remove(manifest.operationID)
                    recovered.append(manifest.operationID)
                }
                if affectedTrackIDSet.insert(manifest.trackID).inserted {
                    affectedTrackIDs.append(manifest.trackID)
                }
            } catch {
                throw recoveryError(
                    preserving: error,
                    manifest: manifest
                )
            }
        }
        return ManagedLyricsRecoveryResult(
            recoveredOperationIDs: recovered,
            rolledBackOperationIDs: rolledBack,
            affectedTrackIDs: affectedTrackIDs
        )
    }
}

private extension ManagedLyricsService {
    func recoveryError(
        preserving error: any Error,
        manifest: ManagedLyricEditManifest
    ) -> any Error {
        var compensationFailures: [String] = []
        do {
            try manifestStore.quarantine(manifest.operationID)
        } catch {
            compensationFailures.append(error.localizedDescription)
        }
        return managedFileError(
            preserving: error,
            subsystem: .lyrics,
            operationID: manifest.operationID,
            compensationFailures: compensationFailures,
            recoveryDirectory: manifestStore.rootURL
        )
    }

    func prepareOperation(
        document: LyricDocument,
        trackID: UUID
    ) async throws -> ManagedLyricEditManifest {
        try package.bootstrapForConfirmedImport(fileManager: fileManager)
        let trackDuration = try await repository.lyricTrackDuration(
            trackID: trackID
        )
        if let issue = document.validationIssues(
            trackDuration: trackDuration
        ).first {
            throw ManagedLyricsServiceError.invalidDocument(issue.message)
        }
        let targetRelativePath = "Lyrics/\(trackID.uuidString).lrc"
        let targetURL = try package.location.resolve(
            relativePath: targetRelativePath,
            directoryHint: .notDirectory
        )
        let previousHash: String? = if fileManager.fileExists(
            atPath: targetURL.path
        ) {
            try await hasher.sha256(of: targetURL)
        } else {
            nil
        }
        let output: Data? = if document.timingStatus == .missing {
            nil
        } else {
            try Data(LineLevelLRC.generate(document).utf8)
        }
        let manifest = ManagedLyricEditManifest(
            operationID: UUID(),
            trackID: trackID,
            targetRelativePath: targetRelativePath,
            previousContentHash: previousHash,
            newContentHash: output.map { hasher.sha256(of: $0) },
            newTimingStatus: output == nil ? nil : document.timingStatus,
            state: .prepared
        )
        try prepare(manifest: manifest, output: output)
        return manifest
    }

    func installOperation(
        _ manifest: ManagedLyricEditManifest
    ) throws -> ManagedLyricEditManifest {
        do {
            try installFile(for: manifest)
            let installed = manifest.advancing(to: .fileInstalled)
            try manifestStore.save(installed)
            return installed
        } catch {
            var compensationFailures: [String] = []
            do {
                try rollbackFile(for: manifest)
            } catch {
                compensationFailures.append(error.localizedDescription)
            }
            if compensationFailures.isEmpty {
                do {
                    try manifestStore.remove(manifest.operationID)
                } catch {
                    compensationFailures.append(error.localizedDescription)
                }
            }
            throw managedFileError(
                preserving: error,
                subsystem: .lyrics,
                operationID: manifest.operationID,
                compensationFailures: compensationFailures,
                recoveryDirectory: manifestStore.operationURL(
                    manifest.operationID
                )
            )
        }
    }

    func commitOperation(
        _ installed: ManagedLyricEditManifest
    ) async throws {
        do {
            try await repository.applyLyricMutation(
                trackID: installed.trackID,
                mutation: installed.mutation
            )
        } catch {
            var compensationFailures: [String] = []
            do {
                try rollbackFile(for: installed)
            } catch {
                compensationFailures.append(error.localizedDescription)
            }
            if compensationFailures.isEmpty {
                do {
                    try manifestStore.remove(installed.operationID)
                } catch {
                    compensationFailures.append(error.localizedDescription)
                }
            }
            throw managedFileError(
                preserving: error,
                subsystem: .lyrics,
                operationID: installed.operationID,
                compensationFailures: compensationFailures,
                recoveryDirectory: manifestStore.operationURL(
                    installed.operationID
                )
            )
        }
        let committed = installed.advancing(to: .metadataCommitted)
        try manifestStore.save(committed)
        try manifestStore.remove(installed.operationID)
    }

    func prepare(
        manifest: ManagedLyricEditManifest,
        output: Data?
    ) throws {
        try manifestStore.save(manifest)
        if let output {
            let stagedURL = manifestStore.stagedURL(
                manifest.operationID
            )
            try output.write(
                to: stagedURL,
                options: .atomic
            )
            let stagedData = try Data(contentsOf: stagedURL)
            guard
                let expectedHash = manifest.newContentHash,
                hasher.sha256(of: stagedData) == expectedHash
            else {
                throw ManagedLyricsServiceError.contentHashMismatch
            }
        }
    }

    func installFile(
        for manifest: ManagedLyricEditManifest
    ) throws {
        let targetURL = try targetURL(for: manifest)
        let previousURL = manifestStore.previousURL(
            manifest.operationID
        )
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.moveItem(at: targetURL, to: previousURL)
        }
        guard manifest.newContentHash != nil else {
            return
        }
        try fileManager.moveItem(
            at: manifestStore.stagedURL(manifest.operationID),
            to: targetURL
        )
    }

    func rollbackFile(
        for manifest: ManagedLyricEditManifest
    ) throws {
        let targetURL = try targetURL(for: manifest)
        let previousURL = manifestStore.previousURL(
            manifest.operationID
        )
        if fileManager.fileExists(atPath: previousURL.path) {
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: previousURL, to: targetURL)
            return
        }
        guard let previousHash = manifest.previousContentHash else {
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            return
        }
        guard fileManager.fileExists(atPath: targetURL.path) else {
            throw ManagedLyricsServiceError.inconsistentRecovery(
                manifest.operationID
            )
        }
        let currentData = try Data(contentsOf: targetURL)
        guard hasher.sha256(of: currentData) == previousHash else {
            throw ManagedLyricsServiceError.inconsistentRecovery(
                manifest.operationID
            )
        }
    }

    func verifyInstalledFile(
        for manifest: ManagedLyricEditManifest
    ) async throws {
        let targetURL = try targetURL(for: manifest)
        guard let expectedHash = manifest.newContentHash else {
            guard !fileManager.fileExists(atPath: targetURL.path) else {
                throw ManagedLyricsServiceError.inconsistentRecovery(
                    manifest.operationID
                )
            }
            return
        }
        guard
            fileManager.fileExists(atPath: targetURL.path),
            try await hasher.sha256(of: targetURL) == expectedHash
        else {
            throw ManagedLyricsServiceError.inconsistentRecovery(
                manifest.operationID
            )
        }
    }

    func targetURL(
        for manifest: ManagedLyricEditManifest
    ) throws -> URL {
        try package.location.resolve(
            relativePath: manifest.targetRelativePath,
            directoryHint: .notDirectory
        )
    }
}
