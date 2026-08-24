import Foundation

protocol LyricsSearchIndexing: AnyObject, Sendable {
    func synchronize() async throws
    func synchronize(trackIDs: Set<UUID>) async throws
    func search(query: String, limit: Int) async throws -> [LyricsSearchMatch]
    func close() async throws
}

actor LyricsSearchIndexer: LyricsSearchIndexing {
    private let package: ManagedLibraryPackage
    private let repository: LibraryRepository
    private let index: LyricsSearchIndex
    private let hasher: ContentHasher

    init(
        package: ManagedLibraryPackage,
        repository: LibraryRepository,
        hasher: ContentHasher = ContentHasher()
    ) throws {
        self.package = package
        self.repository = repository
        let identity = try package.readIdentity()
        let localCatalog = try LocalLibraryCatalogLocation.currentUser(
            identity: identity
        )
        try FileManager.default.createDirectory(
            at: localCatalog.metadataDirectoryURL,
            withIntermediateDirectories: true
        )
        index = try LyricsSearchIndex(
            databaseURL: localCatalog.lyricsSearchDatabaseURL
        )
        self.hasher = hasher
    }

    func synchronize() async throws {
        let metadata = try await repository.allLyricMetadata()
        let indexedHashes = try await index.contentHashes()
        let liveTrackIDs = Set(metadata.map(\.trackID))
        try await index.remove(
            trackIDs: Set(indexedHashes.keys).subtracting(liveTrackIDs)
        )

        let rebuild = await index.needsRebuild
        let changed = rebuild
            ? metadata
            : metadata.filter { indexedHashes[$0.trackID] != $0.contentHash }
        let documents = try await documents(for: changed)
        if rebuild {
            try await index.rebuild(from: documents)
        } else {
            try await index.upsert(documents)
        }
    }

    func synchronize(
        trackIDs: Set<UUID>
    ) async throws {
        guard !trackIDs.isEmpty else { return }
        var metadata: [ManagedLyricMetadata] = []
        var missingTrackIDs: Set<UUID> = []
        for trackID in trackIDs {
            if let value = try await repository.lyricMetadata(trackID: trackID) {
                metadata.append(value)
            } else {
                missingTrackIDs.insert(trackID)
            }
        }
        try await index.remove(trackIDs: missingTrackIDs)
        try await index.upsert(documents(for: metadata))
    }

    func search(
        query: String,
        limit: Int
    ) async throws -> [LyricsSearchMatch] {
        try await index.search(query: query, limit: limit)
    }

    /// Releases the derived SQLite store while its package still exists.
    func close() async throws {
        try await index.close()
    }
}

private extension LyricsSearchIndexer {
    func documents(
        for metadata: [ManagedLyricMetadata]
    ) async throws -> [LyricsSearchDocument] {
        var result: [LyricsSearchDocument] = []
        for metadata in metadata {
            try Task.checkCancellation()
            do {
                try await result.append(
                    contentsOf: documents(for: metadata)
                )
            } catch {
                try? await index.remove(trackIDs: [metadata.trackID])
                throw error
            }
        }
        return result
    }

    func documents(
        for metadata: ManagedLyricMetadata
    ) async throws -> [LyricsSearchDocument] {
        let url = try package.location.resolve(
            relativePath: metadata.relativePath,
            directoryHint: .notDirectory
        )
        let actualHash = try await hasher.sha256(of: url)
        guard actualHash == metadata.contentHash else {
            throw ManagedLyricsServiceError.contentHashMismatch
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        let document = try LineLevelLRC.parse(
            source,
            trackID: metadata.trackID
        )
        return document.lines.enumerated().map { index, line in
            LyricsSearchDocument(
                trackID: metadata.trackID,
                lineIndex: index,
                timestamp: line.startTime,
                text: line.text,
                contentHash: metadata.contentHash
            )
        }
    }
}
