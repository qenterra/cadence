import Foundation

enum ManagedImportRecoveryError: Error, Equatable, LocalizedError, Sendable {
    case inconsistent(importID: UUID, reason: String)

    var errorDescription: String? {
        switch self {
        case let .inconsistent(importID, reason):
            "Import \(importID.uuidString) is inconsistent: \(reason)"
        }
    }
}

struct ManagedImportRecoveryResult: Equatable, Sendable {
    let recoveredImportIDs: [UUID]
    let discardedImportIDs: [UUID]

    static let empty = ManagedImportRecoveryResult(
        recoveredImportIDs: [],
        discardedImportIDs: []
    )
}

actor ManagedLibraryImportRecovery {
    private let destination: ManagedLibraryImportDestination
    private let manifestStore: ManagedImportManifestStore
    private let hasher: ContentHasher

    init(
        destination: ManagedLibraryImportDestination,
        hasher: ContentHasher = ContentHasher()
    ) {
        self.destination = destination
        manifestStore = ManagedImportManifestStore(
            package: destination.package
        )
        self.hasher = hasher
    }

    func recover() async throws -> ManagedImportRecoveryResult {
        let manifests = try manifestStore.loadRecoverableManifests()
        guard !manifests.isEmpty else {
            return .empty
        }

        var recovered: [UUID] = []
        var discarded: [UUID] = []
        for manifest in manifests {
            switch manifest.state {
            case .prepared, .copied:
                try await discardUncommitted(manifest)
                discarded.append(manifest.importID)
            case .filesCommitted:
                if try await recoverFilesCommitted(manifest) {
                    recovered.append(manifest.importID)
                } else {
                    discarded.append(manifest.importID)
                }
            case .storeCommitted:
                try await finalizeStoreCommitted(manifest)
                recovered.append(manifest.importID)
            case .complete:
                try manifestStore.remove(importID: manifest.importID)
                recovered.append(manifest.importID)
            case .rollbackRequired:
                try await discardRollbackRequired(manifest)
                discarded.append(manifest.importID)
            }
        }
        return ManagedImportRecoveryResult(
            recoveredImportIDs: recovered,
            discardedImportIDs: discarded
        )
    }

    private func recoverFilesCommitted(
        _ manifest: ManagedImportManifest
    ) async throws -> Bool {
        try await verifyCommittedAssets(manifest)
        let repository = try await destination.prepareRepository()
        let state = try await repository.importSessionState(
            importID: manifest.importID
        )
        if state == nil {
            do {
                _ = try await repository.commitImport(manifest)
            } catch {
                try removeFinalAssetsOwnedBy(
                    manifest,
                    requireMissingStagedAsset: false
                )
                try manifestStore.remove(importID: manifest.importID)
                return false
            }
        } else if state != .storeCommitted, state != .complete {
            throw ManagedImportRecoveryError.inconsistent(
                importID: manifest.importID,
                reason: "SwiftData contains an unexpected import state."
            )
        }

        let storeCommitted = try manifest.advancing(
            to: .storeCommitted
        )
        try manifestStore.save(storeCommitted)
        try await finalizeStoreCommitted(storeCommitted)
        return true
    }

    private func finalizeStoreCommitted(
        _ manifest: ManagedImportManifest
    ) async throws {
        try await verifyCommittedAssets(manifest)
        let repository = try await destination.prepareRepository()
        let state = try await repository.importSessionState(
            importID: manifest.importID
        )
        guard state == .storeCommitted || state == .complete else {
            throw ManagedImportRecoveryError.inconsistent(
                importID: manifest.importID,
                reason: "SwiftData rows are missing after files were committed."
            )
        }
        if state == .storeCommitted {
            try await repository.completeImport(importID: manifest.importID)
        }
        let complete = try manifest.advancing(to: .complete)
        try manifestStore.save(complete)
        try manifestStore.remove(importID: manifest.importID)
    }

    private func discardUncommitted(
        _ manifest: ManagedImportManifest
    ) async throws {
        let repository = await destination.currentRepository()
        let hasSession = try await repository?.importSessionState(
            importID: manifest.importID
        ) != nil
        if hasSession {
            throw ManagedImportRecoveryError.inconsistent(
                importID: manifest.importID,
                reason: "SwiftData rows exist for an uncommitted manifest."
            )
        }
        try removeFinalAssetsOwnedBy(
            manifest,
            requireMissingStagedAsset: true
        )
        try manifestStore.remove(importID: manifest.importID)
    }

    private func discardRollbackRequired(
        _ manifest: ManagedImportManifest
    ) async throws {
        let repository = await destination.currentRepository()
        let hasSession = try await repository?.importSessionState(
            importID: manifest.importID
        ) != nil
        if hasSession {
            throw ManagedImportRecoveryError.inconsistent(
                importID: manifest.importID,
                reason: "Rollback cannot delete assets owned by SwiftData."
            )
        }
        try removeFinalAssetsOwnedBy(
            manifest,
            requireMissingStagedAsset: true
        )
        try manifestStore.remove(importID: manifest.importID)
    }

    private func verifyCommittedAssets(
        _ manifest: ManagedImportManifest
    ) async throws {
        for entry in manifest.entries where entry.state == .copied {
            let audioURL = try destination.package.location.resolve(
                relativePath: entry.relativeMediaPath
            )
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw ManagedImportRecoveryError.inconsistent(
                    importID: manifest.importID,
                    reason: "Managed audio is missing."
                )
            }
            let audioHash = try await hasher.sha256(of: audioURL)
            guard audioHash == entry.expectedAudioHash else {
                throw ManagedImportRecoveryError.inconsistent(
                    importID: manifest.importID,
                    reason: "Managed audio hash does not match."
                )
            }
            if let lyric = entry.lyric {
                guard let expectedHash = lyric.contentHash else {
                    continue
                }
                let lyricURL = try destination.package.location.resolve(
                    relativePath: lyric.relativePath
                )
                guard
                    FileManager.default.fileExists(atPath: lyricURL.path),
                    try await hasher.sha256(of: lyricURL) == expectedHash
                else {
                    throw ManagedImportRecoveryError.inconsistent(
                        importID: manifest.importID,
                        reason: "Managed lyrics do not match."
                    )
                }
            }
        }
    }

    private func removeFinalAssetsOwnedBy(
        _ manifest: ManagedImportManifest,
        requireMissingStagedAsset: Bool
    ) throws {
        for entry in manifest.entries {
            try removeIfPresent(
                importID: manifest.importID,
                relativePath: entry.relativeMediaPath,
                requireMissingStagedAsset: requireMissingStagedAsset
            )
            if let lyricPath = entry.lyric?.relativePath {
                try removeIfPresent(
                    importID: manifest.importID,
                    relativePath: lyricPath,
                    requireMissingStagedAsset: requireMissingStagedAsset
                )
            }
        }
    }

    private func removeIfPresent(
        importID: UUID,
        relativePath: String,
        requireMissingStagedAsset: Bool
    ) throws {
        if requireMissingStagedAsset {
            let stagedURL = try manifestStore.stagedURL(
                importID: importID,
                relativePath: relativePath
            )
            guard !FileManager.default.fileExists(atPath: stagedURL.path) else {
                return
            }
        }
        let url = try destination.package.location.resolve(
            relativePath: relativePath
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
}
