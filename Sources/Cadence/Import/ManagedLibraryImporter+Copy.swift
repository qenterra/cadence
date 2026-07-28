import Foundation

extension ManagedLibraryImporter {
    func copyToStaging(
        manifest: ManagedImportManifest,
        progress: @escaping @Sendable (
            ManagedImportProgress
        ) async -> Void
    ) async throws -> [ManagedImportManifest.Entry] {
        var nextIndex = 0
        var completedCount = 0
        var copiedBytes: Int64 = 0
        var results: [Int: ManagedImportManifest.Entry] = [:]

        return try await withThrowingTaskGroup(
            of: (Int, ManagedImportManifest.Entry).self,
            returning: [ManagedImportManifest.Entry].self
        ) { group in
            let initialCount = min(
                manifest.entries.count,
                maximumConcurrentCopies
            )
            while nextIndex < initialCount {
                addCopyTask(
                    index: nextIndex,
                    manifest: manifest,
                    group: &group
                )
                nextIndex += 1
            }

            while let (index, entry) = try await group.next() {
                results[index] = entry
                completedCount += 1
                copiedBytes += entry.sizeInBytes
                await progress(
                    ManagedImportProgress(
                        completedCount: completedCount,
                        totalCount: manifest.entries.count,
                        copiedByteCount: copiedBytes,
                        currentFilename: entry.originalFilename,
                        isCommitting: false
                    )
                )
                if nextIndex < manifest.entries.count {
                    addCopyTask(
                        index: nextIndex,
                        manifest: manifest,
                        group: &group
                    )
                    nextIndex += 1
                }
            }
            return manifest.entries.indices.compactMap { results[$0] }
        }
    }

    func addCopyTask(
        index: Int,
        manifest: ManagedImportManifest,
        group: inout ThrowingTaskGroup<
            (Int, ManagedImportManifest.Entry),
            any Error
        >
    ) {
        let entry = manifest.entries[index]
        let manifestStore = manifestStore
        let hasher = hasher
        group.addTask {
            try Task.checkCancellation()
            var copiedEntry = try await copyAudio(
                entry,
                importID: manifest.importID,
                manifestStore: manifestStore,
                hasher: hasher
            )
            copiedEntry.lyric = try await copyLyricsIfValid(
                entry,
                importID: manifest.importID,
                manifestStore: manifestStore,
                hasher: hasher
            )
            try await copyArtworkIfPresent(
                entry,
                importID: manifest.importID,
                manifestStore: manifestStore,
                hasher: hasher
            )
            return (index, copiedEntry)
        }
    }

    func commitFiles(
        _ manifest: ManagedImportManifest
    ) throws {
        let targets = try manifest.entries.flatMap { entry in
            var paths = [entry.relativeMediaPath]
            if let lyricPath = entry.lyric?.relativePath {
                paths.append(lyricPath)
            }
            if let artworkPath = entry.artwork?.relativePath {
                paths.append(artworkPath)
            }
            return try paths.map {
                try destination.package.location.resolve(
                    relativePath: $0
                )
            }
        }
        if let collision = targets.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) {
            throw ManagedLibraryImportError.targetCollision(
                collision.path
            )
        }

        for entry in manifest.entries where entry.state == .copied {
            try moveStagedAsset(
                importID: manifest.importID,
                relativePath: entry.relativeMediaPath
            )
            if let lyricPath = entry.lyric?.relativePath {
                try moveStagedAsset(
                    importID: manifest.importID,
                    relativePath: lyricPath
                )
            }
            if let artworkPath = entry.artwork?.relativePath {
                try moveStagedAsset(
                    importID: manifest.importID,
                    relativePath: artworkPath
                )
            }
        }
    }

    private func moveStagedAsset(
        importID: UUID,
        relativePath: String
    ) throws {
        let source = try manifestStore.stagedURL(
            importID: importID,
            relativePath: relativePath
        )
        let target = try destination.package.location.resolve(
            relativePath: relativePath
        )
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw ManagedLibraryImportError.targetCollision(target.path)
        }
        try FileManager.default.moveItem(at: source, to: target)
    }
}

private func copyAudio(
    _ entry: ManagedImportManifest.Entry,
    importID: UUID,
    manifestStore: ManagedImportManifestStore,
    hasher: ContentHasher
) async throws -> ManagedImportManifest.Entry {
    let sourceURL = URL(filePath: entry.sourceAudioPath)
    let stagedURL = try manifestStore.stagedURL(
        importID: importID,
        relativePath: entry.relativeMediaPath
    )
    try FileManager.default.createDirectory(
        at: stagedURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
    guard try await hasher.sha256(of: stagedURL)
        == entry.expectedAudioHash
    else {
        throw ManagedLibraryImportError.stagedHashMismatch(
            entry.originalFilename
        )
    }
    var copiedEntry = entry
    copiedEntry.state = .copied
    return copiedEntry
}

private func copyLyricsIfValid(
    _ entry: ManagedImportManifest.Entry,
    importID: UUID,
    manifestStore: ManagedImportManifestStore,
    hasher: ContentHasher
) async throws -> ManagedImportManifest.LyricAsset? {
    guard
        let sourcePath = entry.sourceLyricPath,
        var lyric = entry.lyric
    else {
        return nil
    }
    do {
        let sourceURL = URL(filePath: sourcePath)
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let document = try LineLevelLRC.parse(source, trackID: 0)
        let stagedURL = try manifestStore.stagedURL(
            importID: importID,
            relativePath: lyric.relativePath
        )
        try FileManager.default.createDirectory(
            at: stagedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
        lyric.contentHash = try await hasher.sha256(of: stagedURL)
        lyric.timingStatus = document.timingStatus.storageValue
        return lyric
    } catch {
        return nil
    }
}

private func copyArtworkIfPresent(
    _ entry: ManagedImportManifest.Entry,
    importID: UUID,
    manifestStore: ManagedImportManifestStore,
    hasher: ContentHasher
) async throws {
    guard let artwork = entry.artwork else {
        return
    }
    guard
        let payload = await MetadataReader().readEmbeddedArtwork(
            url: URL(filePath: entry.sourceAudioPath)
        ),
        payload.metadata.contentHash == artwork.contentHash,
        hasher.sha256(of: payload.data) == artwork.contentHash
    else {
        throw ManagedLibraryImportError.changedSource(
            entry.sourceAudioPath
        )
    }
    let stagedURL = try manifestStore.stagedURL(
        importID: importID,
        relativePath: artwork.relativePath
    )
    try FileManager.default.createDirectory(
        at: stagedURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try payload.data.write(to: stagedURL, options: .atomic)
}

extension ImportInspectionCandidate {
    var linkedLyricURL: URL? {
        if case let .linked(url) = lyrics {
            return url
        }
        return nil
    }
}

private extension LyricTimingStatus {
    var storageValue: String {
        switch self {
        case .missing:
            "missing"
        case .unsynchronized:
            "unsynchronized"
        case .partiallySynchronized:
            "partiallySynchronized"
        case .synchronized:
            "synchronized"
        }
    }
}
