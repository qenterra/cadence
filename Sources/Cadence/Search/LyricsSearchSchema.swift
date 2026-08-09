import GRDB

enum LyricsSearchSchema {
    static let currentVersion = 1

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("lyrics-search-v1") { database in
            try database.execute(sql: """
            CREATE TABLE lyrics_search_documents (
                track_id TEXT PRIMARY KEY NOT NULL,
                content_hash TEXT NOT NULL
            ) WITHOUT ROWID
            """)
            try database.execute(sql: """
            CREATE VIRTUAL TABLE lyrics_search_fts USING fts5(
                track_id UNINDEXED,
                line_index UNINDEXED,
                timestamp UNINDEXED,
                text,
                content_hash UNINDEXED,
                tokenize = 'unicode61 remove_diacritics 2'
            )
            """)
            try database.execute(
                sql: "PRAGMA user_version = \(currentVersion)"
            )
        }
        return migrator
    }
}
