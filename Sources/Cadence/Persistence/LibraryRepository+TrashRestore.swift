import Foundation
import SwiftData

extension LibraryRepository {
    func restoreTrash(
        operationID: UUID,
        location: ManagedLibraryLocation
    ) throws {
        let manifest = try ManagedTrashManifestStore(location: location)
            .read(operationID: operationID)
        let operation = try trashOperationRecord(id: operationID)
        let restoredFiles = try restoreFiles(
            manifest: manifest,
            location: location
        )

        do {
            try restoreCatalog(from: manifest)
            modelContext.delete(operation)
            try modelContext.save()
            removeRestoredOperationDirectory(
                operationID: operationID,
                location: location
            )
        } catch {
            modelContext.rollback()
            returnFilesToTrash(restoredFiles)
            throw error
        }
    }
}

private extension LibraryRepository {
    func trashOperationRecord(id: UUID) throws -> TrashOperationRecord {
        let predicate = #Predicate<TrashOperationRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw LibraryTrashError.invalidManifest
        }
        return record
    }

    func restoreFiles(
        manifest: ManagedTrashManifest,
        location: ManagedLibraryLocation
    ) throws -> [(restored: URL, trashed: URL)] {
        var moved: [(restored: URL, trashed: URL)] = []
        do {
            for path in manifest.originalRelativePaths {
                let restored = try location.resolve(relativePath: path)
                let trashed = try location.resolve(
                    relativePath: "Trash/\(manifest.operationID)/\(path)"
                )
                guard
                    !FileManager.default.fileExists(atPath: restored.path),
                    FileManager.default.fileExists(atPath: trashed.path)
                else {
                    throw LibraryTrashError.destinationConflict
                }
                try FileManager.default.createDirectory(
                    at: restored.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: trashed, to: restored)
                moved.append((restored, trashed))
            }
            return moved
        } catch {
            returnFilesToTrash(moved)
            throw error
        }
    }

    func returnFilesToTrash(
        _ files: [(restored: URL, trashed: URL)]
    ) {
        for file in files.reversed() {
            try? FileManager.default.createDirectory(
                at: file.trashed.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.moveItem(
                at: file.restored,
                to: file.trashed
            )
        }
    }

    func removeRestoredOperationDirectory(
        operationID: UUID,
        location: ManagedLibraryLocation
    ) {
        let directory = ManagedLibraryPackage(location: location)
            .trashDirectoryURL
            .appending(
                path: operationID.uuidString,
                directoryHint: .isDirectory
            )
        try? FileManager.default.removeItem(at: directory)
    }

    func restoreCatalog(from manifest: ManagedTrashManifest) throws {
        let trackIDs = manifest.tracks.map(\.id)
        let existingTracks = try modelContext.fetch(
            FetchDescriptor<TrackRecord>(
                predicate: #Predicate { trackIDs.contains($0.id) }
            )
        )
        guard existingTracks.isEmpty else {
            throw LibraryTrashError.destinationConflict
        }

        let artists = try restoreArtists(manifest.artists)
        let albums = try restoreAlbums(
            manifest.albums,
            artists: artists
        )
        let tracks = restoreTracks(
            manifest.tracks,
            artists: artists,
            albums: albums
        )
        restoreLyrics(manifest.lyrics, tracks: tracks)
        try restoreArtwork(manifest.artworks)
        try restoreTags(from: manifest)
        try restorePlaylistEntries(from: manifest)
        try refreshRestoredCatalog(albums: albums, artists: artists)
    }

    func restoreArtists(
        _ snapshots: [TrashArtistSnapshot]
    ) throws -> [UUID: ArtistRecord] {
        let ids = snapshots.map(\.id)
        let existing = try modelContext.fetch(
            FetchDescriptor<ArtistRecord>(
                predicate: #Predicate { ids.contains($0.id) }
            )
        )
        var records = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.id, $0) }
        )
        for snapshot in snapshots where records[snapshot.id] == nil {
            let record = ArtistRecord(
                id: snapshot.id,
                name: snapshot.name,
                isFavorite: snapshot.isFavorite,
                favoriteDate: snapshot.favoriteDate,
                customArtworkID: snapshot.customArtworkID
            )
            modelContext.insert(record)
            records[snapshot.id] = record
        }
        return records
    }

    func restoreAlbums(
        _ snapshots: [TrashAlbumSnapshot],
        artists: [UUID: ArtistRecord]
    ) throws -> [UUID: AlbumRecord] {
        let ids = snapshots.map(\.id)
        let existing = try modelContext.fetch(
            FetchDescriptor<AlbumRecord>(
                predicate: #Predicate { ids.contains($0.id) }
            )
        )
        var records = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.id, $0) }
        )
        for snapshot in snapshots where records[snapshot.id] == nil {
            let record = AlbumRecord(
                id: snapshot.id,
                title: snapshot.title,
                artist: snapshot.artistID.flatMap { artists[$0] },
                year: snapshot.year,
                dateAdded: snapshot.dateAdded,
                isFavorite: snapshot.isFavorite,
                favoriteDate: snapshot.favoriteDate,
                customArtworkID: snapshot.customArtworkID
            )
            modelContext.insert(record)
            records[snapshot.id] = record
        }
        return records
    }

    func restoreTracks(
        _ snapshots: [TrashTrackSnapshot],
        artists: [UUID: ArtistRecord],
        albums: [UUID: AlbumRecord]
    ) -> [UUID: TrackRecord] {
        var records: [UUID: TrackRecord] = [:]
        for snapshot in snapshots {
            let record = TrackRecord(
                id: snapshot.id,
                originalFilename: snapshot.originalFilename,
                title: snapshot.title,
                duration: snapshot.duration,
                codec: snapshot.codec,
                container: snapshot.container,
                sampleRate: snapshot.sampleRate,
                channelCount: snapshot.channelCount,
                bitDepth: snapshot.bitDepth,
                bitrate: snapshot.bitrate,
                contentHash: snapshot.contentHash,
                relativeMediaPath: snapshot.relativeMediaPath,
                importSessionID: snapshot.importSessionID,
                artist: snapshot.artistID.flatMap { artists[$0] },
                album: snapshot.albumID.flatMap { albums[$0] },
                trackNumber: snapshot.trackNumber,
                discNumber: snapshot.discNumber,
                sourceFrameCount: snapshot.sourceFrameCount,
                dateAdded: snapshot.dateAdded,
                lastPlayedAt: snapshot.lastPlayedAt,
                playCount: snapshot.playCount,
                skipCount: snapshot.skipCount,
                isFavorite: snapshot.isFavorite,
                spatialFormat: snapshot.spatialFormat,
                sourceMetadata: snapshot.sourceMetadata,
                customArtworkID: snapshot.customArtworkID,
                replayGainTrackGain: snapshot.replayGainTrackGain,
                replayGainTrackPeak: snapshot.replayGainTrackPeak
            )
            modelContext.insert(record)
            records[snapshot.id] = record
        }
        return records
    }
}
