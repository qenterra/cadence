import Foundation
import SwiftData

extension LibraryRepository {
    func restoreLyrics(
        _ snapshots: [TrashLyricSnapshot],
        tracks: [UUID: TrackRecord]
    ) {
        for snapshot in snapshots {
            guard let track = tracks[snapshot.trackID] else {
                continue
            }
            modelContext.insert(
                LyricRecord(
                    id: snapshot.id,
                    relativePath: snapshot.relativePath,
                    textEncoding: snapshot.textEncoding,
                    parsingStatus: snapshot.parsingStatus,
                    contentHash: snapshot.contentHash,
                    timingStatus: lyricTimingStatus(
                        rawValue: snapshot.timingStatusRawValue
                    ),
                    modifiedAt: snapshot.modifiedAt,
                    track: track
                )
            )
        }
    }

    func restoreArtwork(
        _ snapshots: [TrashArtworkSnapshot]
    ) throws {
        let ids = snapshots.map(\.id)
        let existing = try modelContext.fetch(
            FetchDescriptor<ArtworkRecord>(
                predicate: #Predicate { ids.contains($0.id) }
            )
        )
        guard existing.isEmpty else {
            throw LibraryTrashError.destinationConflict
        }
        for snapshot in snapshots {
            modelContext.insert(
                ArtworkRecord(
                    id: snapshot.id,
                    ownerKind: snapshot.ownerKind,
                    ownerID: snapshot.ownerID,
                    relativeOriginalPath: snapshot.relativeOriginalPath,
                    relativeThumbnailPath: snapshot.relativeThumbnailPath,
                    format: snapshot.format,
                    pixelWidth: snapshot.pixelWidth,
                    pixelHeight: snapshot.pixelHeight,
                    cropScale: snapshot.cropScale,
                    normalizedOffsetX: snapshot.normalizedOffsetX,
                    normalizedOffsetY: snapshot.normalizedOffsetY,
                    contentHash: snapshot.contentHash,
                    revision: snapshot.revision
                )
            )
        }
    }

    func restoreTags(
        from manifest: ManagedTrashManifest
    ) throws {
        let tagIDs = Array(
            Set(
                manifest.tagAssignments.map(\.tagID)
                    + manifest.tagExclusions.map(\.tagID)
            )
        )
        let liveTagIDs = try Set(
            modelContext.fetch(
                FetchDescriptor<TagRecord>(
                    predicate: #Predicate { tagIDs.contains($0.id) }
                )
            ).map(\.id)
        )
        for snapshot in manifest.tagAssignments
            where liveTagIDs.contains(snapshot.tagID) {
            modelContext.insert(
                TagAssignmentRecord(
                    id: snapshot.id,
                    targetKind: snapshot.targetKind,
                    targetID: snapshot.targetID,
                    tagID: snapshot.tagID,
                    assignedAt: snapshot.assignedAt
                )
            )
        }
        for snapshot in manifest.tagExclusions
            where liveTagIDs.contains(snapshot.tagID) {
            modelContext.insert(
                TagExclusionRecord(
                    id: snapshot.id,
                    trackID: snapshot.trackID,
                    tagID: snapshot.tagID,
                    excludedAt: snapshot.excludedAt
                )
            )
        }
    }

    func restorePlaylistEntries(
        from manifest: ManagedTrashManifest
    ) throws {
        let snapshots = manifest.playlistEntries ?? []
        guard !snapshots.isEmpty else {
            return
        }
        let playlistIDs = Array(Set(snapshots.map(\.playlistID)))
        let livePlaylistIDs = try Set(
            modelContext.fetch(
                FetchDescriptor<PlaylistRecord>(
                    predicate: #Predicate {
                        playlistIDs.contains($0.id)
                    }
                )
            )
            .map(\.id)
        )
        for playlistID in livePlaylistIDs {
            let playlistSnapshots = snapshots
                .filter { $0.playlistID == playlistID }
                .sorted { $0.position < $1.position }
            let predicate = #Predicate<PlaylistEntryRecord> {
                $0.playlistID == playlistID
            }
            var existing = try modelContext.fetch(
                FetchDescriptor(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.position)]
                )
            )
            var existingTrackIDs = Set(existing.map(\.trackID))
            for snapshot in playlistSnapshots
                where existingTrackIDs.insert(snapshot.trackID).inserted {
                let insertion = min(
                    max(snapshot.position, 0),
                    existing.count
                )
                for entry in existing where entry.position >= insertion {
                    entry.position += 1
                }
                let restored = PlaylistEntryRecord(
                    id: snapshot.id,
                    playlistID: snapshot.playlistID,
                    trackID: snapshot.trackID,
                    position: insertion
                )
                modelContext.insert(restored)
                existing.append(restored)
                existing.sort { $0.position < $1.position }
            }
        }
    }

    func refreshRestoredCatalog(
        albums: [UUID: AlbumRecord],
        artists: [UUID: ArtistRecord]
    ) throws {
        for (id, album) in albums {
            let tracks = try modelContext.fetch(
                FetchDescriptor<TrackRecord>(
                    predicate: #Predicate { $0.album?.id == id }
                )
            )
            album.trackCount = tracks.count
            album.totalDuration = tracks.reduce(0) {
                $0 + $1.duration
            }
        }
        for (id, artist) in artists {
            let credits = try modelContext.fetch(
                FetchDescriptor<TrackArtistCreditRecord>(
                    predicate: #Predicate { $0.artistID == id }
                )
            )
            let albums = try modelContext.fetch(
                FetchDescriptor<AlbumRecord>(
                    predicate: #Predicate { $0.artist?.id == id }
                )
            )
            artist.trackCount = Set(credits.map(\.trackID)).count
            artist.albumCount = albums.count
        }
    }
}

private extension LibraryRepository {
    func lyricTimingStatus(rawValue: String) -> LyricTimingStatus {
        switch rawValue {
        case "unsynchronized":
            .unsynchronized
        case "partiallySynchronized":
            .partiallySynchronized
        case "synchronized":
            .synchronized
        default:
            .missing
        }
    }
}
