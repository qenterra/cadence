import Foundation
import GRDB

struct LyricsSearchDocument: Equatable, Sendable {
    let trackID: UUID
    let lineIndex: Int
    let timestamp: TimeInterval?
    let text: String
    let contentHash: String
}

struct LyricsSearchMatch: Identifiable, Hashable, Sendable {
    var id: UUID {
        trackID
    }

    let trackID: UUID
    let lineIndex: Int
    let timestamp: TimeInterval?
    let snippet: String
}

enum LyricsSearchIndexError: Error, Equatable, LocalizedError, Sendable {
    case inconsistentContentHash(UUID)

    var errorDescription: String? {
        switch self {
        case let .inconsistentContentHash(trackID):
            "Lyric lines for track \(trackID.uuidString) have inconsistent content hashes."
        }
    }
}

actor LyricsSearchIndex {
    private static let searchBatchSize = 256
    private static let maximumSearchRows = 4096

    private let databaseURL: URL
    private var database: DatabaseQueue
    private(set) var needsRebuild: Bool

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        let opened = try Self.openRecovering(at: databaseURL)
        database = opened.database
        needsRebuild = opened.recovered
    }

    func upsert(
        _ documents: [LyricsSearchDocument]
    ) async throws {
        let groups = try Self.validatedGroups(documents)
        guard !groups.isEmpty else { return }
        do {
            try await database.write { database in
                for (trackID, lines) in groups {
                    try Task.checkCancellation()
                    try Self.upsert(
                        trackID: trackID,
                        lines: lines,
                        database: database,
                        skipsUnchanged: true
                    )
                }
            }
        } catch let error as DatabaseError where Self.isCorruption(error) {
            try recoverDatabase()
            try await upsert(documents)
        }
    }

    func rebuild(
        from documents: [LyricsSearchDocument]
    ) async throws {
        let groups = try Self.validatedGroups(documents)
        try await database.write { database in
            try database.execute(sql: "DELETE FROM lyrics_search_fts")
            try database.execute(sql: "DELETE FROM lyrics_search_documents")
            for (trackID, lines) in groups {
                try Task.checkCancellation()
                try Self.upsert(
                    trackID: trackID,
                    lines: lines,
                    database: database,
                    skipsUnchanged: false
                )
            }
        }
        needsRebuild = false
    }

    func remove(
        trackIDs: Set<UUID>
    ) async throws {
        guard !trackIDs.isEmpty else { return }
        try await database.write { database in
            for trackID in trackIDs {
                let value = trackID.uuidString
                try database.execute(
                    sql: "DELETE FROM lyrics_search_fts WHERE track_id = ?",
                    arguments: [value]
                )
                try database.execute(
                    sql: "DELETE FROM lyrics_search_documents WHERE track_id = ?",
                    arguments: [value]
                )
            }
        }
    }

    func contentHashes() async throws -> [UUID: String] {
        try await database.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT track_id, content_hash FROM lyrics_search_documents"
            )
            return Dictionary(
                uniqueKeysWithValues: rows.compactMap { row in
                    guard
                        let rawTrackID: String = row["track_id"],
                        let trackID = UUID(uuidString: rawTrackID),
                        let contentHash: String = row["content_hash"]
                    else {
                        return nil
                    }
                    return (trackID, contentHash)
                }
            )
        }
    }

    func search(
        query: String,
        limit: Int
    ) async throws -> [LyricsSearchMatch] {
        guard limit > 0, let expression = Self.ftsExpression(query) else {
            return []
        }
        do {
            return try await database.read { database in
                try Self.search(
                    database: database,
                    expression: expression,
                    limit: limit
                )
            }
        } catch let error as DatabaseError where Self.isCorruption(error) {
            try recoverDatabase()
            return []
        }
    }

    /// Closes the derived search database before its managed-library package
    /// is moved or deleted. GRDB otherwise keeps WAL descriptors alive after
    /// the package path has disappeared, which SQLite treats as an API error.
    func close() throws {
        try database.close()
    }

    private func recoverDatabase() throws {
        try database.close()
        try Self.removeDatabaseFiles(at: databaseURL)
        database = try Self.makeDatabase(at: databaseURL)
        needsRebuild = true
    }
}

private extension LyricsSearchIndex {
    struct OpenedDatabase {
        let database: DatabaseQueue
        let recovered: Bool
    }

    static func openRecovering(
        at url: URL
    ) throws -> OpenedDatabase {
        do {
            return try OpenedDatabase(
                database: makeDatabase(at: url),
                recovered: false
            )
        } catch let error as DatabaseError where isCorruption(error) {
            try removeDatabaseFiles(at: url)
            return try OpenedDatabase(
                database: makeDatabase(at: url),
                recovered: true
            )
        }
    }

    static func makeDatabase(
        at url: URL
    ) throws -> DatabaseQueue {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.label = "Cadence.LyricsSearch"
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA journal_mode = WAL")
            try database.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        let database = try DatabaseQueue(
            path: url.path,
            configuration: configuration
        )
        try LyricsSearchSchema.migrator.migrate(database)
        let integrity = try database.read { database in
            try String.fetchOne(database, sql: "PRAGMA quick_check")
        }
        guard integrity == "ok" else {
            throw DatabaseError(
                resultCode: .SQLITE_CORRUPT,
                message: "Lyrics search integrity check failed."
            )
        }
        return database
    }

    static func removeDatabaseFiles(
        at url: URL
    ) throws {
        for suffix in ["", "-wal", "-shm"] {
            let candidate = URL(filePath: url.path + suffix)
            if FileManager.default.fileExists(atPath: candidate.path) {
                try FileManager.default.removeItem(at: candidate)
            }
        }
    }

    static func isCorruption(
        _ error: DatabaseError
    ) -> Bool {
        error.resultCode == .SQLITE_CORRUPT
            || error.resultCode == .SQLITE_NOTADB
    }

    static func validatedGroups(
        _ documents: [LyricsSearchDocument]
    ) throws -> [UUID: [LyricsSearchDocument]] {
        let groups = Dictionary(grouping: documents, by: \LyricsSearchDocument.trackID)
        for (trackID, lines) in groups {
            guard Set(lines.map(\.contentHash)).count <= 1 else {
                throw LyricsSearchIndexError.inconsistentContentHash(trackID)
            }
        }
        return groups
    }

    static func upsert(
        trackID: UUID,
        lines: [LyricsSearchDocument],
        database: Database,
        skipsUnchanged: Bool
    ) throws {
        guard let contentHash = lines.first?.contentHash else { return }
        let trackID = trackID.uuidString
        if skipsUnchanged {
            let existingHash = try String.fetchOne(
                database,
                sql: "SELECT content_hash FROM lyrics_search_documents WHERE track_id = ?",
                arguments: [trackID]
            )
            guard existingHash != contentHash else { return }
        }
        try database.execute(
            sql: "DELETE FROM lyrics_search_fts WHERE track_id = ?",
            arguments: [trackID]
        )
        for line in lines where !line.text.isEmpty {
            try database.execute(
                sql: "INSERT INTO lyrics_search_fts VALUES (?, ?, ?, ?, ?)",
                arguments: [
                    trackID,
                    line.lineIndex,
                    line.timestamp,
                    line.text,
                    contentHash,
                ]
            )
        }
        try database.execute(
            sql: """
            INSERT INTO lyrics_search_documents(track_id, content_hash) VALUES (?, ?)
            ON CONFLICT(track_id) DO UPDATE SET content_hash = excluded.content_hash
            """,
            arguments: [trackID, contentHash]
        )
    }

    static func ftsExpression(
        _ query: String
    ) -> String? {
        let tokens = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " AND ")
    }

    static func search(
        database: Database,
        expression: String,
        limit: Int
    ) throws -> [LyricsSearchMatch] {
        var matches: [LyricsSearchMatch] = []
        var seenTrackIDs: Set<UUID> = []
        var offset = 0
        while matches.count < limit, offset < maximumSearchRows {
            try Task.checkCancellation()
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT track_id, line_index, timestamp,
                       highlight(lyrics_search_fts, 3, '<mark>', '</mark>') AS snippet,
                       bm25(lyrics_search_fts)
                FROM lyrics_search_fts
                WHERE lyrics_search_fts MATCH ?
                ORDER BY bm25(lyrics_search_fts)
                LIMIT ? OFFSET ?
                """,
                arguments: [expression, searchBatchSize, offset]
            )
            for row in rows {
                guard
                    let rawTrackID: String = row["track_id"],
                    let trackID = UUID(uuidString: rawTrackID),
                    seenTrackIDs.insert(trackID).inserted
                else {
                    continue
                }
                matches.append(
                    LyricsSearchMatch(
                        trackID: trackID,
                        lineIndex: row["line_index"],
                        timestamp: row["timestamp"],
                        snippet: row["snippet"]
                    )
                )
                if matches.count == limit {
                    break
                }
            }
            guard rows.count == searchBatchSize else { break }
            offset += rows.count
        }
        return matches
    }
}
