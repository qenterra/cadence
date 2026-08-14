import Foundation
import SwiftData

extension LibraryRepository {
    func restoreTrash(
        operationID: UUID,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient = .live
    ) throws {
        let manifest = try ManagedTrashManifestStore(location: location)
            .read(operationID: operationID)
        let operation = try trashOperationRecord(id: operationID)
        var restoredFiles: [(restored: URL, trashed: URL)] = []
        var phase = LibraryTrashTransactionPhase.restoreFiles

        do {
            try restoreFiles(
                manifest: manifest,
                location: location,
                fileClient: fileClient,
                restored: &restoredFiles
            )
            phase = .restoreCatalog
            try restoreCatalog(from: manifest)
            modelContext.delete(operation)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            let compensationFailures = returnFilesToTrash(
                restoredFiles,
                fileClient: fileClient
            )
            throw LibraryTrashTransactionError(
                operationID: operationID,
                phase: phase,
                primaryFailure: error.localizedDescription,
                compensationFailures: compensationFailures,
                recoveryDirectory: trashOperationDirectory(
                    operationID: operationID,
                    location: location
                )
            )
        }

        try cleanupRestoredTrash(
            operationID: operationID,
            location: location,
            fileClient: fileClient
        )
    }
}

private extension LibraryRepository {
    func cleanupRestoredTrash(
        operationID: UUID,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient
    ) throws {
        do {
            try removeTrashOperationDirectory(
                operationID: operationID,
                location: location,
                fileClient: fileClient
            )
        } catch {
            throw LibraryTrashTransactionError(
                operationID: operationID,
                phase: .cleanup,
                primaryFailure: error.localizedDescription,
                compensationFailures: [],
                recoveryDirectory: trashOperationDirectory(
                    operationID: operationID,
                    location: location
                )
            )
        }
    }

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
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient,
        restored: inout [(restored: URL, trashed: URL)]
    ) throws {
        for path in manifest.originalRelativePaths {
            let restoredURL = try location.resolve(relativePath: path)
            let trashedURL = try location.resolve(
                relativePath: "Trash/\(manifest.operationID)/\(path)"
            )
            guard
                !fileClient.fileExists(restoredURL),
                fileClient.fileExists(trashedURL)
            else {
                throw LibraryTrashError.destinationConflict
            }
            try fileClient.createDirectory(
                restoredURL.deletingLastPathComponent()
            )
            try fileClient.moveItem(trashedURL, restoredURL)
            restored.append((restoredURL, trashedURL))
        }
    }

    func returnFilesToTrash(
        _ files: [(restored: URL, trashed: URL)],
        fileClient: TrashFileClient
    ) -> [String] {
        var failures: [String] = []
        for file in files.reversed() {
            do {
                try fileClient.createDirectory(
                    file.trashed.deletingLastPathComponent()
                )
                try fileClient.moveItem(file.restored, file.trashed)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        return failures
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
        try restoreArtistCredits(
            manifest.artistCredits,
            restoredTracks: tracks,
            artists: artists
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
                isFavorite: snapshot.isFavorite,
                favoriteDate: snapshot.favoriteDate,
                customArtworkID: snapshot.customArtworkID
            )
            modelContext.insert(record)
            records[snapshot.id] = record
        }
        for snapshot in snapshots {
            records[snapshot.id]?.artist = snapshot.artistID.flatMap {
                artists[$0]
            }
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
                lastPlayedAt: snapshot.lastPlayedAt,
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

    func restoreArtistCredits(
        _ snapshots: [TrashArtistCreditSnapshot]?,
        restoredTracks: [UUID: TrackRecord],
        artists: [UUID: ArtistRecord]
    ) throws {
        guard let snapshots, !snapshots.isEmpty else {
            restoreLegacyArtistCredits(tracks: restoredTracks.values)
            return
        }

        let trackIDs = Array(Set(snapshots.map(\.trackID)))
        let existingTracks = try modelContext.fetch(
            FetchDescriptor<TrackRecord>(
                predicate: #Predicate { trackIDs.contains($0.id) }
            )
        )
        var tracks = Dictionary(
            uniqueKeysWithValues: existingTracks.map { ($0.id, $0) }
        )
        tracks.merge(restoredTracks) { _, restored in restored }
        let creditIDs = snapshots.map(\.id)
        let existingCreditIDs = try Set(
            modelContext.fetch(
                FetchDescriptor<TrackArtistCreditRecord>(
                    predicate: #Predicate { creditIDs.contains($0.id) }
                )
            ).map(\.id)
        )

        for snapshot in snapshots
            where !existingCreditIDs.contains(snapshot.id) {
            guard
                let track = tracks[snapshot.trackID],
                let artist = artists[snapshot.artistID]
            else {
                continue
            }
            modelContext.insert(
                TrackArtistCreditRecord(
                    id: snapshot.id,
                    track: track,
                    artist: artist,
                    position: snapshot.position,
                    displayArtistName: snapshot.displayArtistName
                )
            )
            if snapshot.position == 0 {
                track.artist = artist
            }
        }
    }

    func restoreLegacyArtistCredits(
        tracks: Dictionary<UUID, TrackRecord>.Values
    ) {
        for track in tracks {
            guard let artist = track.artist else {
                continue
            }
            modelContext.insert(
                TrackArtistCreditRecord(
                    track: track,
                    artist: artist,
                    position: 0,
                    displayArtistName: artist.name
                )
            )
        }
    }
}
