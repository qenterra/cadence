import Foundation
import SwiftData

extension LibraryRepository {
    func makeTrashManifest(
        plan: LibraryTrashPlan,
        operationID: UUID,
        targetKind: TrashTargetKind
    ) throws -> ManagedTrashManifest {
        let relationships = try trashRelationships(plan: plan)

        return ManagedTrashManifest(
            version: ManagedTrashManifest.currentVersion,
            operationID: operationID,
            targetKind: targetKind,
            createdAt: .now,
            artists: plan.artists.values.map(artistSnapshot).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            albums: plan.albums.values.map(albumSnapshot).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            tracks: plan.tracks.map(trackSnapshot).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            lyrics: plan.tracks.compactMap(\.lyrics).map(lyricSnapshot),
            artworks: plan.artworks.map(artworkSnapshot),
            tagAssignments: relationships.assignments.map(assignmentSnapshot),
            tagExclusions: relationships.exclusions.map(exclusionSnapshot),
            playlistEntries: relationships.playlistEntries.map(
                playlistEntrySnapshot
            ),
            originalRelativePaths: plan.relativePaths
        )
    }
}

private struct TrashRelationships {
    let assignments: [TagAssignmentRecord]
    let exclusions: [TagExclusionRecord]
    let playlistEntries: [PlaylistEntryRecord]
}

private extension LibraryRepository {
    func trashRelationships(
        plan: LibraryTrashPlan
    ) throws -> TrashRelationships {
        let assignmentTargetIDs = Array(
            plan.trackIDs.union(plan.deletedAlbumIDs)
        )
        let trackIDs = Array(plan.trackIDs)
        let assignments = try assignmentTargetIDs.isEmpty
            ? []
            : modelContext.fetch(
                FetchDescriptor<TagAssignmentRecord>(
                    predicate: #Predicate {
                        assignmentTargetIDs.contains($0.targetID)
                    }
                )
            )
        let exclusions = try trackIDs.isEmpty
            ? []
            : modelContext.fetch(
                FetchDescriptor<TagExclusionRecord>(
                    predicate: #Predicate {
                        trackIDs.contains($0.trackID)
                    }
                )
            )
        let playlistEntries = try trackIDs.isEmpty
            ? []
            : modelContext.fetch(
                FetchDescriptor<PlaylistEntryRecord>(
                    predicate: #Predicate {
                        trackIDs.contains($0.trackID)
                    }
                )
            )
        return TrashRelationships(
            assignments: assignments,
            exclusions: exclusions,
            playlistEntries: playlistEntries
        )
    }

    func artistSnapshot(_ artist: ArtistRecord) -> TrashArtistSnapshot {
        TrashArtistSnapshot(
            id: artist.id,
            name: artist.name,
            isFavorite: artist.isFavorite,
            favoriteDate: artist.favoriteDate,
            customArtworkID: artist.customArtworkID
        )
    }

    func albumSnapshot(_ album: AlbumRecord) -> TrashAlbumSnapshot {
        TrashAlbumSnapshot(
            id: album.id,
            title: album.title,
            artistID: album.artist?.id,
            year: album.year,
            dateAdded: album.dateAdded,
            isFavorite: album.isFavorite,
            favoriteDate: album.favoriteDate,
            customArtworkID: album.customArtworkID
        )
    }

    func trackSnapshot(_ track: TrackRecord) -> TrashTrackSnapshot {
        TrashTrackSnapshot(
            id: track.id,
            originalFilename: track.originalFilename,
            title: track.title,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            duration: track.duration,
            sourceFrameCount: track.sourceFrameCount,
            dateAdded: track.dateAdded,
            lastPlayedAt: track.lastPlayedAt,
            playCount: track.playCount,
            skipCount: track.skipCount,
            isFavorite: track.isFavorite,
            codec: track.codec,
            container: track.container,
            sampleRate: track.sampleRate,
            channelCount: track.channelCount,
            bitrate: track.bitrate,
            bitDepth: track.bitDepth,
            spatialFormat: track.spatialFormat,
            contentHash: track.contentHash,
            relativeMediaPath: track.relativeMediaPath,
            sourceMetadata: track.sourceMetadata,
            importSessionID: track.importSessionID,
            customArtworkID: track.customArtworkID,
            replayGainTrackGain: track.replayGainTrackGain,
            replayGainTrackPeak: track.replayGainTrackPeak,
            artistID: track.artist?.id,
            albumID: track.album?.id
        )
    }

    func lyricSnapshot(_ lyric: LyricRecord) -> TrashLyricSnapshot {
        TrashLyricSnapshot(
            id: lyric.id,
            trackID: lyric.trackID,
            relativePath: lyric.relativePath,
            textEncoding: lyric.textEncoding,
            parsingStatus: lyric.parsingStatus,
            timingStatusRawValue: lyric.timingStatusRawValue,
            contentHash: lyric.contentHash,
            modifiedAt: lyric.modifiedAt
        )
    }

    func artworkSnapshot(
        _ artwork: ArtworkRecord
    ) -> TrashArtworkSnapshot {
        TrashArtworkSnapshot(
            id: artwork.id,
            ownerKind: artwork.ownerKind,
            ownerID: artwork.ownerID,
            relativeOriginalPath: artwork.relativeOriginalPath,
            relativeThumbnailPath: artwork.relativeThumbnailPath,
            format: artwork.format,
            pixelWidth: artwork.pixelWidth,
            pixelHeight: artwork.pixelHeight,
            cropScale: artwork.cropScale,
            normalizedOffsetX: artwork.normalizedOffsetX,
            normalizedOffsetY: artwork.normalizedOffsetY,
            contentHash: artwork.contentHash,
            revision: artwork.revision
        )
    }

    func assignmentSnapshot(
        _ assignment: TagAssignmentRecord
    ) -> TrashTagAssignmentSnapshot {
        TrashTagAssignmentSnapshot(
            id: assignment.id,
            targetKind: assignment.targetKind,
            targetID: assignment.targetID,
            tagID: assignment.tagID,
            assignedAt: assignment.assignedAt
        )
    }

    func exclusionSnapshot(
        _ exclusion: TagExclusionRecord
    ) -> TrashTagExclusionSnapshot {
        TrashTagExclusionSnapshot(
            id: exclusion.id,
            trackID: exclusion.trackID,
            tagID: exclusion.tagID,
            excludedAt: exclusion.excludedAt
        )
    }

    func playlistEntrySnapshot(
        _ entry: PlaylistEntryRecord
    ) -> TrashPlaylistEntrySnapshot {
        TrashPlaylistEntrySnapshot(
            id: entry.id,
            playlistID: entry.playlistID,
            trackID: entry.trackID,
            position: entry.position,
            dateAdded: entry.dateAdded
        )
    }
}
