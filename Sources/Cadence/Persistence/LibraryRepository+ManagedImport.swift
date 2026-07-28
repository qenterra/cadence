import Foundation
import SwiftData

enum ManagedImportStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidManifestState(ManagedImportManifest.State)
    case duplicateImportSession(UUID)
    case duplicateTrack(UUID)
    case duplicateContent(String)

    var errorDescription: String? {
        switch self {
        case let .invalidManifestState(state):
            "SwiftData cannot commit an import in the \(state.rawValue) state."
        case let .duplicateImportSession(id):
            "Import session \(id.uuidString) is already committed."
        case let .duplicateTrack(id):
            "Track \(id.uuidString) is already committed."
        case let .duplicateContent(hash):
            "A managed track already owns SHA-256 \(hash)."
        }
    }
}

struct ManagedImportStoreResult: Equatable, Sendable {
    let importID: UUID
    let importedTrackIDs: [UUID]
    let lyricsLinked: Int
    let selectedByteCount: Int64
}

extension LibraryRepository {
    func commitImport(
        _ uncheckedManifest: ManagedImportManifest
    ) throws -> ManagedImportStoreResult {
        let manifest = try uncheckedManifest.validated()
        guard manifest.state == .filesCommitted else {
            throw ManagedImportStoreError.invalidManifestState(
                manifest.state
            )
        }

        let entries = manifest.entries.filter { $0.state == .copied }
        try assertImportIsUncommitted(
            importID: manifest.importID,
            entries: entries
        )

        do {
            try insertImportRecords(entries: entries, manifest: manifest)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        return ManagedImportStoreResult(
            importID: manifest.importID,
            importedTrackIDs: entries.map(\.trackID),
            lyricsLinked: entries.count {
                $0.lyric?.contentHash != nil
            },
            selectedByteCount: entries.reduce(0) {
                $0 + $1.sizeInBytes
            }
        )
    }

    func importedTracks(
        importID: UUID,
        limit: Int = maximumPageSize
    ) throws -> [LibraryTrackProjection] {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        let predicate = #Predicate<TrackRecord> { track in
            track.importSessionID == importID
        }
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.normalizedTitle),
                SortDescriptor(\.sortIdentity),
            ]
        )
        descriptor.fetchLimit = boundedLimit
        return try modelContext.fetch(descriptor).map(
            LibraryProjectionFactory.track
        )
    }

    func importSessionState(
        importID: UUID
    ) throws -> ImportSessionState? {
        let predicate = #Predicate<ImportSessionRecord> { session in
            session.id == importID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.state
    }

    func completeImport(
        importID: UUID,
        completedAt: Date = .now
    ) throws {
        let predicate = #Predicate<ImportSessionRecord> { session in
            session.id == importID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let session = try modelContext.fetch(descriptor).first else {
            throw ManagedImportStoreError.duplicateImportSession(importID)
        }
        session.state = .complete
        session.completedAt = completedAt
        try modelContext.save()
    }

    private func insertImportRecords(
        entries: [ManagedImportManifest.Entry],
        manifest: ManagedImportManifest
    ) throws {
        let artists = try reusableArtists(for: entries)
        let albums = try reusableAlbums(
            for: entries,
            artists: artists,
            dateAdded: manifest.createdAt
        )
        insertEmbeddedArtwork(
            entries: entries,
            albums: albums
        )
        modelContext.insert(
            ImportSessionRecord(
                id: manifest.importID,
                sourceDisplayName: manifest.sourceDisplayName,
                state: .storeCommitted,
                createdAt: manifest.createdAt,
                importedCount: entries.count,
                failedCount: manifest.entries.count - entries.count,
                selectedByteCount: entries.reduce(0) {
                    $0 + $1.sizeInBytes
                },
                manifestVersion: manifest.version
            )
        )

        for entry in entries {
            insertTrack(
                entry,
                importID: manifest.importID,
                dateAdded: manifest.createdAt,
                artists: artists,
                albums: albums
            )
        }
        refreshAggregateCounts(
            entries: entries,
            artists: artists,
            albums: albums
        )
    }

    private func insertEmbeddedArtwork(
        entries: [ManagedImportManifest.Entry],
        albums: [ManagedAlbumIdentity: AlbumRecord]
    ) {
        for entry in entries {
            guard let artwork = entry.artwork else {
                continue
            }
            let albumKey = ManagedAlbumIdentity(
                normalizedArtist: SearchNormalizer.normalize(
                    entry.metadata.artist
                ),
                normalizedTitle: SearchNormalizer.normalize(
                    entry.metadata.album
                )
            )
            guard
                let album = albums[albumKey],
                album.customArtworkID == nil
            else {
                continue
            }
            let record = ArtworkRecord(
                id: artwork.id,
                ownerKind: .album,
                ownerID: album.id,
                relativeOriginalPath: artwork.relativePath,
                format: artwork.format,
                pixelWidth: artwork.pixelWidth,
                pixelHeight: artwork.pixelHeight,
                contentHash: artwork.contentHash
            )
            modelContext.insert(record)
            album.customArtworkID = record.id
        }
    }

    private func insertTrack(
        _ entry: ManagedImportManifest.Entry,
        importID: UUID,
        dateAdded: Date,
        artists: [String: ArtistRecord],
        albums: [ManagedAlbumIdentity: AlbumRecord]
    ) {
        let artistKey = SearchNormalizer.normalize(entry.metadata.artist)
        let albumKey = ManagedAlbumIdentity(
            normalizedArtist: artistKey,
            normalizedTitle: SearchNormalizer.normalize(
                entry.metadata.album
            )
        )
        let track = makeTrack(
            entry: entry,
            importID: importID,
            artist: artists[artistKey],
            album: albums[albumKey],
            dateAdded: dateAdded
        )
        modelContext.insert(track)

        guard
            let lyric = entry.lyric,
            let contentHash = lyric.contentHash
        else {
            return
        }
        modelContext.insert(
            LyricRecord(
                relativePath: lyric.relativePath,
                parsingStatus: .valid,
                contentHash: contentHash,
                timingStatus: lyricTimingStatus(
                    rawValue: lyric.timingStatus
                ),
                track: track
            )
        )
    }

    private func makeTrack(
        entry: ManagedImportManifest.Entry,
        importID: UUID,
        artist: ArtistRecord?,
        album: AlbumRecord?,
        dateAdded: Date
    ) -> TrackRecord {
        TrackRecord(
            id: entry.trackID,
            originalFilename: entry.originalFilename,
            title: entry.metadata.title,
            duration: entry.metadata.duration,
            codec: entry.metadata.codec,
            container: entry.metadata.container,
            sampleRate: entry.metadata.sampleRate,
            channelCount: entry.metadata.channelCount,
            bitDepth: entry.metadata.bitDepth,
            bitrate: entry.metadata.bitrate,
            contentHash: entry.expectedAudioHash,
            relativeMediaPath: entry.relativeMediaPath,
            importSessionID: importID,
            artist: artist,
            album: album,
            trackNumber: entry.metadata.trackNumber,
            discNumber: entry.metadata.discNumber,
            dateAdded: dateAdded,
            spatialFormat: entry.metadata.spatialFormat,
            sourceMetadata: try? JSONEncoder().encode(entry.metadata)
        )
    }

    private func lyricTimingStatus(
        rawValue: String?
    ) -> LyricTimingStatus {
        switch rawValue {
        case "synchronized":
            .synchronized
        case "partiallySynchronized":
            .partiallySynchronized
        case "unsynchronized":
            .unsynchronized
        default:
            .missing
        }
    }
}
