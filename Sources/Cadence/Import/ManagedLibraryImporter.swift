import Foundation

enum ManagedLibraryImportError: Error, Equatable, LocalizedError, Sendable {
    case emptySelection
    case unavailableSource(String)
    case changedSource(String)
    case insufficientCapacity(required: Int64, available: Int64)
    case targetCollision(String)
    case stagedHashMismatch(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "Choose at least one track to import."
        case let .unavailableSource(path):
            "The source is no longer available: \(path)"
        case let .changedSource(path):
            "The source changed after Scan: \(path)"
        case let .insufficientCapacity(required, available):
            "The Cadence folder needs \(required) bytes, but only \(available) are available."
        case let .targetCollision(path):
            "A managed destination already exists: \(path)"
        case let .stagedHashMismatch(path):
            "The staged copy does not match its source: \(path)"
        }
    }
}

enum ManagedImportFailurePoint: String, CaseIterable, Sendable {
    case afterPrepared
    case afterCopied
    case afterFilesCommitted
    case afterStoreCommitted
}

struct ManagedImportInjectedFailure: Error, Sendable {}

struct ManagedImportFailureInjector: Sendable {
    private let operation: @Sendable (
        ManagedImportFailurePoint
    ) throws -> Void

    init(
        operation: @escaping @Sendable (
            ManagedImportFailurePoint
        ) throws -> Void = { _ in }
    ) {
        self.operation = operation
    }

    func callAsFunction(
        _ point: ManagedImportFailurePoint
    ) throws {
        do {
            try operation(point)
        } catch {
            throw ManagedImportInjectedFailure()
        }
    }

    static let disabled = ManagedImportFailureInjector()
}

struct ManagedImportCompletion: Equatable, Sendable {
    let importID: UUID
    let importedTrackIDs: [UUID]
    let lyricsLinked: Int
    let exactDuplicatesSkipped: Int
    let filesNotImported: Int
    let importedByteCount: Int64
}

actor ManagedLibraryImporter {
    static let defaultMaximumConcurrentCopies = 4
    static let minimumCapacityReserve: Int64 = 64 * 1024 * 1024

    let destination: ManagedLibraryImportDestination
    let manifestStore: ManagedImportManifestStore
    let hasher: ContentHasher
    let maximumConcurrentCopies: Int
    let failureInjector: ManagedImportFailureInjector
    private let availableCapacity: @Sendable (URL) throws -> Int64

    init(
        destination: ManagedLibraryImportDestination,
        hasher: ContentHasher = ContentHasher(),
        maximumConcurrentCopies: Int = defaultMaximumConcurrentCopies,
        failureInjector: ManagedImportFailureInjector = .disabled,
        availableCapacity: @escaping @Sendable (URL) throws -> Int64 = {
            let values = try $0.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        }
    ) {
        self.destination = destination
        manifestStore = ManagedImportManifestStore(
            package: destination.package
        )
        self.hasher = hasher
        self.maximumConcurrentCopies = min(
            max(maximumConcurrentCopies, 1),
            Self.defaultMaximumConcurrentCopies
        )
        self.failureInjector = failureInjector
        self.availableCapacity = availableCapacity
    }

    func importCandidates(
        _ candidates: [ImportInspectionCandidate],
        includedIDs: Set<UUID>,
        sourceDisplayName: String,
        progress: @escaping @Sendable (
            ManagedImportProgress
        ) async -> Void = { _ in }
    ) async throws -> ManagedImportCompletion {
        let selected = candidates.filter {
            includedIDs.contains($0.id)
                && $0.failure == nil
                && $0.duplicateDisposition != .exactDuplicate
                && $0.metadata != nil
                && $0.contentHash != nil
        }
        guard !selected.isEmpty else {
            throw ManagedLibraryImportError.emptySelection
        }

        try await revalidate(selected)
        let package = destination.package
        try package.bootstrapForConfirmedImport()
        let repository = try await destination.prepareRepository()
        let importID = UUID()
        let manifest = try makeManifest(
            importID: importID,
            sourceDisplayName: sourceDisplayName,
            candidates: selected
        )
        try manifestStore.save(manifest)
        try failureInjector(.afterPrepared)

        return try await executePreparedImport(
            manifest: manifest,
            repository: repository,
            candidates: candidates,
            selected: selected,
            progress: progress
        )
    }

    private func revalidate(
        _ candidates: [ImportInspectionCandidate]
    ) async throws {
        let selectedBytes = candidates.reduce(Int64(0)) {
            $0 + $1.sizeInBytes
        }
        let reserve = max(
            Self.minimumCapacityReserve,
            selectedBytes / 20
        )
        let available = try availableCapacity(
            capacityProbeURL()
        )
        guard selectedBytes + reserve <= available else {
            throw ManagedLibraryImportError.insufficientCapacity(
                required: selectedBytes + reserve,
                available: available
            )
        }

        for candidate in candidates {
            try Task.checkCancellation()
            let url = candidate.sourceFile.url
            let values: URLResourceValues
            do {
                values = try url.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey]
                )
            } catch {
                throw ManagedLibraryImportError.unavailableSource(url.path)
            }
            guard values.isRegularFile == true else {
                throw ManagedLibraryImportError.unavailableSource(url.path)
            }
            guard Int64(values.fileSize ?? -1) == candidate.sizeInBytes else {
                throw ManagedLibraryImportError.changedSource(url.path)
            }
        }
    }

    /// Capacity metadata is available only for existing filesystem entries.
    /// A first confirmed import may legitimately target a not-yet-created
    /// Music directory, so probe its nearest existing ancestor on that volume.
    private func capacityProbeURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        var candidate = destination.package.location.musicDirectory
        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else {
                throw ManagedLibraryError.musicDirectoryUnavailable
            }
            candidate = parent
        }
        return candidate
    }

    private func makeManifest(
        importID: UUID,
        sourceDisplayName: String,
        candidates: [ImportInspectionCandidate]
    ) throws -> ManagedImportManifest {
        var albumsWithArtwork: Set<ImportMetadataIdentity> = []
        let entries = try candidates.map { candidate in
            let metadata = try require(candidate.metadata)
            let contentHash = try require(candidate.contentHash)
            let fileExtension = candidate.sourceFile.url.pathExtension
                .lowercased()
            let trackID = candidate.id
            let artwork = manifestArtwork(
                for: metadata,
                albumsWithArtwork: &albumsWithArtwork
            )
            return ManagedImportManifest.Entry(
                trackID: trackID,
                sourceAudioPath: candidate.sourceFile.url.path,
                sourceLyricPath: candidate.linkedLyricURL?.path,
                originalFilename: candidate.sourceFilename,
                originalExtension: fileExtension,
                metadata: ManagedImportManifest.Metadata(metadata),
                expectedAudioHash: contentHash,
                sizeInBytes: candidate.sizeInBytes,
                relativeMediaPath: "Media/\(trackID.uuidString).\(fileExtension)",
                lyric: candidate.hasImportableLyrics
                    ?
                    ManagedImportManifest.LyricAsset(
                        relativePath: "Lyrics/\(trackID.uuidString).lrc",
                        contentHash: nil,
                        timingStatus: nil
                    )
                    : nil,
                artwork: artwork,
                state: .pending,
                failureReason: nil
            )
        }
        return try ManagedImportManifest(
            importID: importID,
            sourceDisplayName: sourceDisplayName,
            state: .prepared,
            entries: entries
        ).validated()
    }

    private func manifestArtwork(
        for metadata: ScannedAudioMetadata,
        albumsWithArtwork: inout Set<ImportMetadataIdentity>
    ) -> ManagedImportManifest.ArtworkAsset? {
        let identity = ImportMetadataIdentity(
            artist: metadata.albumArtist ?? metadata.artists.first
                ?? metadata.artist,
            title: metadata.album
        )
        guard
            let embedded = metadata.embeddedArtwork,
            albumsWithArtwork.insert(identity).inserted
        else {
            return nil
        }
        let id = UUID()
        return ManagedImportManifest.ArtworkAsset(
            id: id,
            relativePath:
            "Artwork/Original/\(id.uuidString).\(embedded.format)",
            contentHash: embedded.contentHash,
            format: embedded.format,
            pixelWidth: embedded.pixelWidth,
            pixelHeight: embedded.pixelHeight
        )
    }

    private func require<Value>(
        _ value: Value?
    ) throws -> Value {
        guard let value else {
            throw ManagedLibraryImportError.emptySelection
        }
        return value
    }
}
