import Foundation
import QenTerraFoundation

enum ManagedTrackMetadataTransactionError: Error, LocalizedError {
    case rollbackFailed(original: String, rollback: String, backupURL: URL)
    case inconsistentRecovery(UUID)

    var errorDescription: String? {
        switch self {
        case let .rollbackFailed(original, rollback, backupURL):
            "Cadence changed the audio tags, but could not restore the original file after "
                + "the library update failed (\(original)). The recovery copy remains at "
                + "\(backupURL.path). Restore also failed: \(rollback)"
        case let .inconsistentRecovery(operationID):
            "Cadence could not safely recover metadata edit \(operationID.uuidString)."
        }
    }
}

/// Keeps managed audio and the catalog projection in one recoverable operation.
///
/// The file is cloned before mutation. If catalog persistence fails, the edited
/// file is atomically replaced by that clone. A failed rollback deliberately
/// leaves the clone beside the media file instead of deleting the only recovery
/// artifact.
struct ManagedTrackMetadataTransaction {
    private let editor: ManagedAudioMetadataEditor
    private let reader: MetadataReader
    private let fileManager: FileManager
    private let package: ManagedLibraryPackage?

    init(
        package: ManagedLibraryPackage? = nil,
        editor: ManagedAudioMetadataEditor = ManagedAudioMetadataEditor(),
        reader: MetadataReader = MetadataReader(),
        fileManager: FileManager = .default
    ) {
        self.editor = editor
        self.reader = reader
        self.fileManager = fileManager
        self.package = package
    }

    func perform(
        trackID: UUID,
        fileURL: URL,
        relativeMediaPath: String? = nil,
        edit: ManagedAudioMetadataEdit,
        persist: @MainActor @Sendable (ManagedMetadataRepair) async throws -> Void
    ) async throws -> ScannedAudioMetadata {
        let journal = try await prepareJournal(
            trackID: trackID,
            fileURL: fileURL,
            relativeMediaPath: relativeMediaPath
        )
        let backupURL = journal?.backupURL ?? recoveryURL(for: fileURL)
        if let journal {
            try journal.store.save(journal.manifest)
        }
        try fileManager.copyItem(at: fileURL, to: backupURL)
        var fileWasEdited = false

        do {
            try await editor.write(edit, to: fileURL)
            fileWasEdited = true
            let scanned = try await reader.read(url: fileURL)
            let merged = merging(edit.normalized, into: scanned)
            let sourceMetadata = if let snapshot = merged.sourceMetadata {
                try JSONEncoder().encode(snapshot)
            } else {
                try JSONEncoder().encode(ManagedImportManifest.Metadata(merged))
            }
            let contentHash = try await ContentHasher().sha256(of: fileURL)
            let repair = ManagedMetadataRepair(
                trackID: trackID,
                metadata: ManagedImportManifest.Metadata(merged),
                sourceMetadata: sourceMetadata,
                contentHash: contentHash
            )
            if let journal {
                try journal.store.save(
                    journal.manifest.advancing(
                        to: .fileInstalled,
                        repair: repair
                    )
                )
            }
            try await persist(repair)
            if let journal {
                try journal.store.save(
                    journal.manifest.advancing(
                        to: .metadataCommitted,
                        repair: repair
                    )
                )
                try journal.store.remove(journal.manifest.operationID)
            } else {
                try fileManager.removeItem(at: backupURL)
            }
            return merged
        } catch {
            guard fileWasEdited else {
                try? fileManager.removeItem(at: backupURL)
                if let journal {
                    try? journal.store.remove(journal.manifest.operationID)
                }
                throw error
            }
            do {
                _ = try fileManager.replaceItemAt(
                    fileURL,
                    withItemAt: backupURL,
                    backupItemName: nil,
                    options: []
                )
                if let journal {
                    try journal.store.remove(journal.manifest.operationID)
                }
            } catch let rollbackError {
                throw ManagedTrackMetadataTransactionError.rollbackFailed(
                    original: error.localizedDescription,
                    rollback: rollbackError.localizedDescription,
                    backupURL: backupURL
                )
            }
            throw error
        }
    }

    func recover(repository: LibraryRepository) async throws -> Int {
        guard let package else {
            return 0
        }
        let store = ManagedTrackMetadataEditManifestStore(package: package)
        var recoveredCount = 0
        for manifest in try store.loadRecoverable() {
            let fileURL = try package.location.resolve(
                relativePath: manifest.relativeMediaPath,
                directoryHint: .notDirectory
            )
            let backupURL = store.backupURL(manifest)
            switch manifest.state {
            case .prepared:
                let currentHash = try await ContentHasher().sha256(of: fileURL)
                if currentHash != manifest.originalHash {
                    guard fileManager.fileExists(atPath: backupURL.path) else {
                        throw ManagedTrackMetadataTransactionError
                            .inconsistentRecovery(manifest.operationID)
                    }
                    _ = try fileManager.replaceItemAt(
                        fileURL,
                        withItemAt: backupURL,
                        backupItemName: nil,
                        options: []
                    )
                }
                try store.remove(manifest.operationID)
            case .fileInstalled:
                guard
                    let repair = manifest.repair,
                    try await ContentHasher().sha256(of: fileURL)
                    == manifest.editedHash
                else {
                    throw ManagedTrackMetadataTransactionError
                        .inconsistentRecovery(manifest.operationID)
                }
                _ = try await repository.applyMetadataRepairs([repair])
                try store.save(manifest.advancing(to: .metadataCommitted))
                try store.remove(manifest.operationID)
                recoveredCount += 1
            case .metadataCommitted:
                try store.remove(manifest.operationID)
            }
        }
        return recoveredCount
    }

    private func recoveryURL(for fileURL: URL) -> URL {
        let basename = fileURL.deletingPathExtension().lastPathComponent
        let filename = ".\(basename).cadence-tags-backup-\(UUID().uuidString).\(fileURL.pathExtension)"
        return fileURL.deletingLastPathComponent().appending(
            path: filename,
            directoryHint: .notDirectory
        )
    }

    private struct Journal {
        let store: ManagedTrackMetadataEditManifestStore
        let manifest: ManagedTrackMetadataEditManifest
        let backupURL: URL
    }

    private func prepareJournal(
        trackID: UUID,
        fileURL: URL,
        relativeMediaPath: String?
    ) async throws -> Journal? {
        guard let package, let relativeMediaPath else {
            return nil
        }
        let manifest = try await ManagedTrackMetadataEditManifest(
            operationID: UUID(),
            trackID: trackID,
            relativeMediaPath: relativeMediaPath,
            originalHash: ContentHasher().sha256(of: fileURL),
            state: .prepared
        )
        let store = ManagedTrackMetadataEditManifestStore(package: package)
        return Journal(
            store: store,
            manifest: manifest,
            backupURL: store.backupURL(manifest)
        )
    }

    private func merging(
        _ edit: ManagedAudioMetadataEdit,
        into scanned: ScannedAudioMetadata
    ) -> ScannedAudioMetadata {
        ScannedAudioMetadata(
            title: edit.title,
            artist: edit.artist,
            album: edit.album,
            artists: [edit.artist],
            albumArtist: scanned.albumArtist,
            year: edit.year,
            trackNumber: scanned.trackNumber,
            discNumber: scanned.discNumber,
            duration: scanned.duration,
            codec: scanned.codec,
            container: scanned.container,
            sampleRate: scanned.sampleRate,
            channelCount: scanned.channelCount,
            bitrate: scanned.bitrate,
            bitDepth: scanned.bitDepth,
            spatialFormat: scanned.spatialFormat,
            embeddedArtwork: scanned.embeddedArtwork,
            embeddedLyrics: scanned.embeddedLyrics,
            sourceMetadata: scanned.sourceMetadata
        )
    }
}
