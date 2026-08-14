import Foundation
import SwiftData

private struct ArtistTrashCandidates {
    let artist: ArtistRecord
    let tracks: [TrackRecord]
    let credits: [TrackArtistCreditRecord]
}

private struct ArtistTrashPartition {
    let deleted: [TrackRecord]
    let retained: [TrackRecord]
}

extension LibraryRepository {
    func compensateFailedTrash(
        primary: any Error,
        context: TrashCompensationContext,
        fileClient: TrashFileClient
    ) -> LibraryTrashTransactionError {
        var failures = restoreMovedPaths(
            context.movedPaths,
            fileClient: fileClient
        )
        if context.manifestWasWritten, failures.isEmpty {
            do {
                try removeTrashOperationDirectory(
                    operationID: context.operationID,
                    location: context.location,
                    fileClient: fileClient
                )
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        return LibraryTrashTransactionError(
            operationID: context.operationID,
            phase: context.phase,
            primaryFailure: primary.localizedDescription,
            compensationFailures: failures,
            recoveryDirectory: trashOperationDirectory(
                operationID: context.operationID,
                location: context.location
            )
        )
    }

    func makeTrashPlan(
        kind: TrashTargetKind,
        id: UUID
    ) throws -> LibraryTrashPlan {
        if kind == .artist {
            return try makeArtistTrashPlan(id: id)
        }
        let tracks = try trashTargetTracks(kind: kind, id: id)
        guard !tracks.isEmpty else {
            throw LibraryTrashError.missingTarget
        }
        let trackIDs = Set(tracks.map(\.id))
        let credits = try creditRecords(trackIDs: trackIDs)
        let albums = relatedAlbums(tracks)
        let artists = try relatedArtists(tracks, credits: credits)
        let deletedAlbumIDs = emptyAlbumIDs(
            albums,
            afterRemoving: trackIDs
        )
        let deletedArtistIDs = try emptyArtistIDs(
            artists,
            afterRemoving: trackIDs
        )
        let artworks = try artworkRecordsForTrash(
            trackIDs: trackIDs,
            albumIDs: deletedAlbumIDs,
            artistIDs: deletedArtistIDs
        )
        return LibraryTrashPlan(
            tracks: tracks,
            retainedTracks: [],
            credits: credits,
            trackIDs: trackIDs,
            albums: albums,
            artists: artists,
            deletedAlbumIDs: deletedAlbumIDs,
            deletedArtistIDs: deletedArtistIDs,
            targetArtistID: nil,
            artworks: artworks,
            relativePaths: trashRelativePaths(
                tracks: tracks,
                artworks: artworks
            )
        )
    }

    func makeArtistTrashPlan(id: UUID) throws -> LibraryTrashPlan {
        let candidates = try artistTrashCandidates(id: id)
        let partition = partitionArtistTracks(candidates, artistID: id)
        let deletedTrackIDs = Set(partition.deleted.map(\.id))
        let removedCredits = removedArtistCredits(
            candidates,
            partition: partition,
            artistID: id
        )

        var albums = relatedAlbums(partition.deleted)
        let ownedAlbumPredicate = #Predicate<AlbumRecord> {
            $0.artist?.id == id
        }
        for album in try modelContext.fetch(
            FetchDescriptor(predicate: ownedAlbumPredicate)
        ) {
            albums[album.id] = album
        }
        let deletedAlbumIDs = emptyAlbumIDs(
            albums,
            afterRemoving: deletedTrackIDs
        )
        var artists = try relatedArtists(
            partition.deleted,
            credits: removedCredits
        )
        artists[candidates.artist.id] = candidates.artist
        let deletedArtistIDs = try Set([candidates.artist.id]).union(
            emptyArtistIDs(artists, afterRemoving: deletedTrackIDs)
        )
        let artworks = try artworkRecordsForTrash(
            trackIDs: deletedTrackIDs,
            albumIDs: deletedAlbumIDs,
            artistIDs: deletedArtistIDs
        )
        return LibraryTrashPlan(
            tracks: partition.deleted,
            retainedTracks: partition.retained,
            credits: removedCredits,
            trackIDs: deletedTrackIDs,
            albums: albums,
            artists: artists,
            deletedAlbumIDs: deletedAlbumIDs,
            deletedArtistIDs: deletedArtistIDs,
            targetArtistID: candidates.artist.id,
            artworks: artworks,
            relativePaths: trashRelativePaths(
                tracks: partition.deleted,
                artworks: artworks
            )
        )
    }

    private func removedArtistCredits(
        _ candidates: ArtistTrashCandidates,
        partition: ArtistTrashPartition,
        artistID: UUID
    ) -> [TrackArtistCreditRecord] {
        let deletedIDs = Set(partition.deleted.map(\.id))
        let retainedIDs = Set(partition.retained.map(\.id))
        return candidates.credits.filter {
            deletedIDs.contains($0.trackID)
                || (retainedIDs.contains($0.trackID) && $0.artistID == artistID)
        }
    }

    private func artistTrashCandidates(id: UUID) throws -> ArtistTrashCandidates {
        let artistPredicate = #Predicate<ArtistRecord> { $0.id == id }
        guard let targetArtist = try modelContext.fetch(
            FetchDescriptor(predicate: artistPredicate)
        ).first else {
            throw LibraryTrashError.missingTarget
        }

        let targetCreditPredicate = #Predicate<TrackArtistCreditRecord> {
            $0.artistID == id
        }
        let targetCredits = try modelContext.fetch(
            FetchDescriptor(predicate: targetCreditPredicate)
        )
        let creditedTrackIDs = Array(Set(targetCredits.map(\.trackID)))
        var creditedTracks = try modelContext.fetch(
            FetchDescriptor<TrackRecord>(
                predicate: #Predicate {
                    creditedTrackIDs.contains($0.id)
                }
            )
        )
        let legacyPredicate = #Predicate<TrackRecord> {
            $0.artist?.id == id
        }
        let legacyTracks = try modelContext.fetch(
            FetchDescriptor(predicate: legacyPredicate)
        )
        let knownTrackIDs = Set(creditedTracks.map(\.id))
        creditedTracks.append(
            contentsOf: legacyTracks.filter {
                !knownTrackIDs.contains($0.id)
            }
        )

        let credits = try creditRecords(
            trackIDs: Set(creditedTracks.map(\.id))
        )
        return ArtistTrashCandidates(
            artist: targetArtist,
            tracks: creditedTracks,
            credits: credits
        )
    }

    private func partitionArtistTracks(
        _ candidates: ArtistTrashCandidates,
        artistID: UUID
    ) -> ArtistTrashPartition {
        let creditsByTrackID = Dictionary(
            grouping: candidates.credits,
            by: \.trackID
        )
        var deletedTracks: [TrackRecord] = []
        var retainedTracks: [TrackRecord] = []
        for track in candidates.tracks {
            let credits = creditsByTrackID[track.id] ?? []
            if credits.filter({ $0.artistID != artistID }).isEmpty {
                deletedTracks.append(track)
            } else {
                retainedTracks.append(track)
            }
        }
        return ArtistTrashPartition(
            deleted: deletedTracks,
            retained: retainedTracks
        )
    }
}
