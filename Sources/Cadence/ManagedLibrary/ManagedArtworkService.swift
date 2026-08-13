import Foundation

struct ManagedArtworkRecoveryResult: Equatable, Sendable {
    let recoveredOperationIDs: [UUID]
    let rolledBackOperationIDs: [UUID]

    static let empty = ManagedArtworkRecoveryResult(
        recoveredOperationIDs: [],
        rolledBackOperationIDs: []
    )
}

actor ManagedArtworkService {
    private let package: ManagedLibraryPackage
    private let repository: LibraryRepository
    private let manifestStore: ManagedArtworkEditManifestStore
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
        manifestStore = ManagedArtworkEditManifestStore(package: package)
        self.hasher = hasher
        self.fileManager = fileManager
    }

    func setArtwork(_ request: ManagedArtworkEditRequest) async throws -> UUID {
        _ = try await recover()
        let manifest = try await prepareSet(request)
        let installed = try install(manifest)
        try await commit(installed)
        guard let artworkID = manifest.newArtwork?.id else {
            throw ManagedArtworkEditError.inconsistentRecovery(
                manifest.operationID
            )
        }
        return artworkID
    }

    func removeArtwork(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID
    ) async throws {
        _ = try await recover()
        let manifest = try await prepareRemoval(
            ownerKind: ownerKind,
            ownerID: ownerID
        )
        let installed = try install(manifest)
        try await commit(installed)
    }

    func recover() async throws -> ManagedArtworkRecoveryResult {
        let manifests = try manifestStore.loadRecoverable()
        guard !manifests.isEmpty else {
            return .empty
        }

        var recovered: [UUID] = []
        var rolledBack: [UUID] = []
        for manifest in manifests {
            do {
                switch manifest.state {
                case .prepared:
                    if try await preparedOperationWasInstalled(manifest) {
                        try await completeInstalledOperation(manifest)
                        recovered.append(manifest.operationID)
                    } else {
                        try manifestStore.remove(manifest.operationID)
                        rolledBack.append(manifest.operationID)
                    }
                case .fileInstalled:
                    try await completeInstalledOperation(manifest)
                    recovered.append(manifest.operationID)
                case .metadataCommitted:
                    try await repository.applyArtworkEdit(manifest)
                    try await verifyInstalledFile(for: manifest)
                    try cleanup(manifest)
                    recovered.append(manifest.operationID)
                }
            } catch {
                var compensationFailures: [String] = []
                do {
                    try manifestStore.quarantine(manifest.operationID)
                } catch {
                    compensationFailures.append(error.localizedDescription)
                }
                throw managedFileError(
                    preserving: error,
                    subsystem: .artwork,
                    operationID: manifest.operationID,
                    compensationFailures: compensationFailures,
                    recoveryDirectory: manifestStore.rootURL
                )
            }
        }
        return ManagedArtworkRecoveryResult(
            recoveredOperationIDs: recovered,
            rolledBackOperationIDs: rolledBack
        )
    }
}

private extension ManagedArtworkService {
    func prepareSet(
        _ request: ManagedArtworkEditRequest
    ) async throws -> ManagedArtworkEditManifest {
        try package.bootstrapForConfirmedImport(fileManager: fileManager)
        guard
            let payload = MetadataReader().artworkPayload(data: request.data)
        else {
            throw ManagedArtworkEditError.invalidImage
        }
        let previous = try await repository.artworkEditSnapshot(
            ownerKind: request.ownerKind,
            ownerID: request.ownerID
        )
        let id = UUID()
        let artwork = ManagedArtworkDescriptor(
            id: id,
            ownerKind: request.ownerKind,
            ownerID: request.ownerID,
            relativeOriginalPath: "Artwork/Original/\(id.uuidString)."
                + payload.metadata.format,
            relativeThumbnailPath: nil,
            format: payload.metadata.format,
            pixelWidth: payload.metadata.pixelWidth,
            pixelHeight: payload.metadata.pixelHeight,
            cropScale: Double(request.scale),
            normalizedOffsetX: request.normalizedOffset.width,
            normalizedOffsetY: request.normalizedOffset.height,
            contentHash: payload.metadata.contentHash,
            revision: 0
        )
        let manifest = ManagedArtworkEditManifest(
            operationID: UUID(),
            ownerKind: request.ownerKind,
            ownerID: request.ownerID,
            mutationKind: .set,
            previousArtwork: previous,
            newArtwork: artwork,
            state: .prepared
        )
        try manifestStore.save(manifest)
        let stagedURL = manifestStore.stagedURL(manifest.operationID)
        try request.data.write(to: stagedURL, options: .atomic)
        guard try hasher.sha256(of: Data(contentsOf: stagedURL))
            == artwork.contentHash
        else {
            throw ManagedArtworkEditError.contentHashMismatch
        }
        return manifest
    }

    func prepareRemoval(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID
    ) async throws -> ManagedArtworkEditManifest {
        try package.bootstrapForConfirmedImport(fileManager: fileManager)
        let previous = try await repository.artworkEditSnapshot(
            ownerKind: ownerKind,
            ownerID: ownerID
        )
        let manifest = ManagedArtworkEditManifest(
            operationID: UUID(),
            ownerKind: ownerKind,
            ownerID: ownerID,
            mutationKind: .remove,
            previousArtwork: previous,
            newArtwork: nil,
            state: .prepared
        )
        try manifestStore.save(manifest)
        return manifest
    }

    func install(
        _ manifest: ManagedArtworkEditManifest
    ) throws -> ManagedArtworkEditManifest {
        if let newArtwork = manifest.newArtwork {
            let target = try targetURL(for: newArtwork)
            guard !fileManager.fileExists(atPath: target.path) else {
                throw ManagedArtworkEditError.inconsistentRecovery(
                    manifest.operationID
                )
            }
            try fileManager.moveItem(
                at: manifestStore.stagedURL(manifest.operationID),
                to: target
            )
        }
        let installed = manifest.advancing(to: .fileInstalled)
        try manifestStore.save(installed)
        return installed
    }

    func commit(_ installed: ManagedArtworkEditManifest) async throws {
        try await repository.applyArtworkEdit(installed)
        let committed = installed.advancing(to: .metadataCommitted)
        try manifestStore.save(committed)
        try cleanup(committed)
    }

    func completeInstalledOperation(
        _ manifest: ManagedArtworkEditManifest
    ) async throws {
        try await verifyInstalledFile(for: manifest)
        try await repository.applyArtworkEdit(manifest)
        let committed = manifest.advancing(to: .metadataCommitted)
        try manifestStore.save(committed)
        try cleanup(committed)
    }

    func preparedOperationWasInstalled(
        _ manifest: ManagedArtworkEditManifest
    ) async throws -> Bool {
        guard let newArtwork = manifest.newArtwork else {
            return false
        }
        let target = try targetURL(for: newArtwork)
        guard fileManager.fileExists(atPath: target.path) else {
            return false
        }
        try await verifyInstalledFile(for: manifest)
        return true
    }

    func verifyInstalledFile(
        for manifest: ManagedArtworkEditManifest
    ) async throws {
        guard let newArtwork = manifest.newArtwork else {
            return
        }
        let target = try targetURL(for: newArtwork)
        guard
            fileManager.fileExists(atPath: target.path),
            try await hasher.sha256(of: target) == newArtwork.contentHash
        else {
            throw ManagedArtworkEditError.inconsistentRecovery(
                manifest.operationID
            )
        }
    }

    func cleanup(_ manifest: ManagedArtworkEditManifest) throws {
        for path in manifest.previousArtwork?.relativePaths ?? [] {
            let url = try package.location.resolve(
                relativePath: path,
                directoryHint: .notDirectory
            )
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }
            try fileManager.removeItem(at: url)
        }
        try manifestStore.remove(manifest.operationID)
    }

    func targetURL(for artwork: ManagedArtworkDescriptor) throws -> URL {
        try package.location.resolve(
            relativePath: artwork.relativeOriginalPath,
            directoryHint: .notDirectory
        )
    }
}
