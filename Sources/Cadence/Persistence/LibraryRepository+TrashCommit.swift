import Foundation
import SwiftData

extension LibraryRepository {
    func commitTrash(
        _ plan: LibraryTrashPlan,
        operationID: UUID,
        targetKind: TrashTargetKind
    ) throws {
        let encoder = JSONEncoder()
        var operationTargetIDs = plan.trackIDs
        if let targetArtistID = plan.targetArtistID {
            operationTargetIDs.insert(targetArtistID)
        }
        try modelContext.insert(
            TrashOperationRecord(
                id: operationID,
                targetKind: targetKind,
                targetIDsData: encoder.encode(Array(operationTargetIDs)),
                originalRelativePathsData: encoder.encode(
                    plan.relativePaths
                ),
                completedAt: .now
            )
        )
        try removeTagReferences(
            trackIDs: plan.trackIDs,
            albumIDs: plan.deletedAlbumIDs
        )
        try removePlaylistReferences(trackIDs: plan.trackIDs)
        try reassignRetainedRelationships(in: plan)
        plan.credits.forEach(modelContext.delete)
        plan.tracks.forEach(modelContext.delete)
        plan.artworks.forEach(modelContext.delete)
        try refreshAfterTrash(plan)
        try modelContext.save()
    }

    func reassignRetainedRelationships(
        in plan: LibraryTrashPlan
    ) throws {
        guard let deletedArtistID = plan.targetArtistID else {
            return
        }
        let removedCreditIDs = Set(plan.credits.map(\.id))
        let candidateTrackIDs = Set(
            plan.retainedTracks.map(\.id)
                + plan.albums.values.flatMap { $0.tracks.map(\.id) }
        ).subtracting(plan.trackIDs)
        let remainingCredits = try creditRecords(trackIDs: candidateTrackIDs)
            .filter { !removedCreditIDs.contains($0.id) }
        let remainingArtistIDs = Array(Set(remainingCredits.map(\.artistID)))
        let remainingArtists = try modelContext.fetch(
            FetchDescriptor<ArtistRecord>(
                predicate: #Predicate {
                    remainingArtistIDs.contains($0.id)
                }
            )
        )
        let artistsByID = Dictionary(
            uniqueKeysWithValues: remainingArtists.map { ($0.id, $0) }
        )
        let creditsByTrackID = Dictionary(
            grouping: remainingCredits,
            by: \.trackID
        ).mapValues { $0.sorted { $0.position < $1.position } }

        for track in plan.retainedTracks {
            track.artist = creditsByTrackID[track.id]?.first.flatMap {
                artistsByID[$0.artistID]
            }
        }
        for album in plan.albums.values
            where !plan.deletedAlbumIDs.contains(album.id)
            && album.artist?.id == deletedArtistID {
            let replacement = album.tracks
                .filter { !plan.trackIDs.contains($0.id) }
                .sorted { $0.sortIdentity < $1.sortIdentity }
                .compactMap { track in
                    creditsByTrackID[track.id]?.first.flatMap {
                        artistsByID[$0.artistID]
                    }
                        ?? (track.artist?.id == deletedArtistID
                            ? nil
                            : track.artist)
                }
                .first
            album.artist = replacement
        }
    }

    func relatedAlbums(
        _ tracks: [TrackRecord]
    ) -> [UUID: AlbumRecord] {
        tracks.reduce(into: [:]) { albums, track in
            if let album = track.album {
                albums[album.id] = album
            }
        }
    }

    func relatedArtists(
        _ tracks: [TrackRecord],
        credits: [TrackArtistCreditRecord]
    ) throws -> [UUID: ArtistRecord] {
        var artists: [UUID: ArtistRecord] = tracks.reduce(into: [:]) { artists, track in
            if let artist = track.artist {
                artists[artist.id] = artist
            }
        }
        let artistIDs = Array(Set(credits.map(\.artistID)))
        let creditedArtists = try modelContext.fetch(
            FetchDescriptor<ArtistRecord>(
                predicate: #Predicate { artistIDs.contains($0.id) }
            )
        )
        for artist in creditedArtists {
            artists[artist.id] = artist
        }
        return artists
    }

    func creditRecords(
        trackIDs: Set<UUID>
    ) throws -> [TrackArtistCreditRecord] {
        let ids = Array(trackIDs)
        guard !ids.isEmpty else {
            return []
        }
        let predicate = #Predicate<TrackArtistCreditRecord> {
            ids.contains($0.trackID)
        }
        return try modelContext.fetch(FetchDescriptor(predicate: predicate))
    }

    func emptyAlbumIDs(
        _ albums: [UUID: AlbumRecord],
        afterRemoving trackIDs: Set<UUID>
    ) -> Set<UUID> {
        Set(albums.values.compactMap { album in
            album.tracks.allSatisfy { trackIDs.contains($0.id) }
                ? album.id
                : nil
        })
    }

    func emptyArtistIDs(
        _ artists: [UUID: ArtistRecord],
        afterRemoving trackIDs: Set<UUID>
    ) throws -> Set<UUID> {
        var emptyIDs: Set<UUID> = []
        for artist in artists.values {
            let artistID = artist.id
            let predicate = #Predicate<TrackArtistCreditRecord> {
                $0.artistID == artistID
            }
            let hasRemainingCredit = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).contains { !trackIDs.contains($0.trackID) }
            let hasRemainingAlbum = artist.albums.contains { album in
                album.tracks.contains { !trackIDs.contains($0.id) }
            }
            if !hasRemainingCredit, !hasRemainingAlbum {
                emptyIDs.insert(artist.id)
            }
        }
        return emptyIDs
    }

    func trashTargetTracks(
        kind: TrashTargetKind,
        id: UUID
    ) throws -> [TrackRecord] {
        let descriptor: FetchDescriptor<TrackRecord>
        switch kind {
        case .track:
            let predicate = #Predicate<TrackRecord> { $0.id == id }
            descriptor = FetchDescriptor(predicate: predicate)
        case .album:
            let predicate = #Predicate<TrackRecord> {
                $0.album?.id == id
            }
            descriptor = FetchDescriptor(predicate: predicate)
        case .artist:
            let predicate = #Predicate<TrackRecord> {
                $0.artist?.id == id
            }
            descriptor = FetchDescriptor(predicate: predicate)
        }
        return try modelContext.fetch(descriptor)
    }

    func artworkRecordsForTrash(
        trackIDs: Set<UUID>,
        albumIDs: Set<UUID>,
        artistIDs: Set<UUID>
    ) throws -> [ArtworkRecord] {
        let ownerIDs = Array(trackIDs.union(albumIDs).union(artistIDs))
        guard !ownerIDs.isEmpty else {
            return []
        }
        let predicate = #Predicate<ArtworkRecord> {
            ownerIDs.contains($0.ownerID)
        }
        return try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
    }

    func trashRelativePaths(
        tracks: [TrackRecord],
        artworks: [ArtworkRecord]
    ) -> [String] {
        var paths: Set<String> = []
        for track in tracks {
            paths.insert(track.relativeMediaPath)
            if let lyricPath = track.lyrics?.relativePath {
                paths.insert(lyricPath)
            }
        }
        for artwork in artworks {
            paths.insert(artwork.relativeOriginalPath)
            if let thumbnail = artwork.relativeThumbnailPath {
                paths.insert(thumbnail)
            }
        }
        return paths.sorted()
    }

    func removeTagReferences(
        trackIDs: Set<UUID>,
        albumIDs: Set<UUID>
    ) throws {
        let targetIDs = Array(trackIDs.union(albumIDs))
        if !targetIDs.isEmpty {
            let assignmentPredicate = #Predicate<TagAssignmentRecord> {
                targetIDs.contains($0.targetID)
            }
            for record in try modelContext.fetch(
                FetchDescriptor(predicate: assignmentPredicate)
            ) {
                modelContext.delete(record)
            }
        }
        let ids = Array(trackIDs)
        if !ids.isEmpty {
            let exclusionPredicate = #Predicate<TagExclusionRecord> {
                ids.contains($0.trackID)
            }
            for record in try modelContext.fetch(
                FetchDescriptor(predicate: exclusionPredicate)
            ) {
                modelContext.delete(record)
            }
        }
    }

    func removePlaylistReferences(
        trackIDs: Set<UUID>
    ) throws {
        let ids = Array(trackIDs)
        guard !ids.isEmpty else {
            return
        }
        let predicate = #Predicate<PlaylistEntryRecord> {
            ids.contains($0.trackID)
        }
        let removedEntries = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
        let playlistIDs = Set(removedEntries.map(\.playlistID))
        removedEntries.forEach(modelContext.delete)
        for playlistID in playlistIDs {
            let remainingPredicate = #Predicate<PlaylistEntryRecord> {
                $0.playlistID == playlistID
                    && !ids.contains($0.trackID)
            }
            let remaining = try modelContext.fetch(
                FetchDescriptor(
                    predicate: remainingPredicate,
                    sortBy: [SortDescriptor(\.position)]
                )
            )
            for (position, entry) in remaining.enumerated() {
                entry.position = position
            }
        }
    }

    func refreshAfterTrash(_ plan: LibraryTrashPlan) throws {
        var removedAlbumIDs: Set<UUID> = []
        for album in plan.albums.values {
            let remaining = album.tracks.filter {
                !plan.trackIDs.contains($0.id)
            }
            if remaining.isEmpty {
                removedAlbumIDs.insert(album.id)
                modelContext.delete(album)
            } else {
                album.trackCount = remaining.count
                album.totalDuration = remaining.reduce(0) {
                    $0 + $1.duration
                }
            }
        }
        for artist in plan.artists.values {
            if plan.deletedArtistIDs.contains(artist.id) {
                modelContext.delete(artist)
                continue
            }
            let artistID = artist.id
            let creditPredicate = #Predicate<TrackArtistCreditRecord> {
                $0.artistID == artistID
            }
            let remainingTracks = try Set(
                modelContext.fetch(
                    FetchDescriptor(predicate: creditPredicate)
                ).map(\.trackID)
            )
            let remainingAlbums = artist.albums.filter {
                !removedAlbumIDs.contains($0.id)
            }
            if remainingTracks.isEmpty, remainingAlbums.isEmpty {
                modelContext.delete(artist)
            } else {
                artist.trackCount = remainingTracks.count
                artist.albumCount = remainingAlbums.count
            }
        }
    }
}
