import Foundation
import SwiftData

enum LibraryTrashError: Error, LocalizedError, Sendable {
    case destinationConflict
    case invalidManifest
    case missingManagedFile(String)
    case missingTarget
    case unavailableLibrary

    var errorDescription: String? {
        switch self {
        case .destinationConflict:
            "A managed file already exists at the restore destination."
        case .invalidManifest:
            "The Trash operation cannot be restored safely."
        case let .missingManagedFile(path):
            "A managed file is missing: \(path)"
        case .missingTarget:
            "The selected library item no longer exists."
        case .unavailableLibrary:
            "The managed library is unavailable."
        }
    }
}

struct LibraryTrashPlan {
    let tracks: [TrackRecord]
    let retainedTracks: [TrackRecord]
    let credits: [TrackArtistCreditRecord]
    let trackIDs: Set<UUID>
    let albums: [UUID: AlbumRecord]
    let artists: [UUID: ArtistRecord]
    let deletedAlbumIDs: Set<UUID>
    let deletedArtistIDs: Set<UUID>
    let targetArtistID: UUID?
    let artworks: [ArtworkRecord]
    let relativePaths: [String]
}

private struct TrashCompensationContext {
    let operationID: UUID
    let phase: LibraryTrashTransactionPhase
    let manifestWasWritten: Bool
    let movedPaths: [(original: URL, trashed: URL)]
    let location: ManagedLibraryLocation
}

extension LibraryRepository {
    func trashTracks(
        targetIDs: [UUID],
        location: ManagedLibraryLocation
    ) throws -> [UUID] {
        var seen: Set<UUID> = []
        var operationIDs: [UUID] = []
        for targetID in targetIDs where seen.insert(targetID).inserted {
            try operationIDs.append(
                trash(
                    targetKind: .track,
                    targetID: targetID,
                    location: location
                )
            )
        }
        return operationIDs
    }

    func trash(
        targetKind: TrashTargetKind,
        targetID: UUID,
        location: ManagedLibraryLocation,
        operationID: UUID = UUID(),
        fileClient: TrashFileClient = .live
    ) throws -> UUID {
        let plan = try makeTrashPlan(
            kind: targetKind,
            id: targetID
        )
        let manifest = try makeTrashManifest(
            plan: plan,
            operationID: operationID,
            targetKind: targetKind
        )
        let manifestStore = ManagedTrashManifestStore(location: location)
        var movedPaths: [(original: URL, trashed: URL)] = []
        var phase = LibraryTrashTransactionPhase.writeManifest
        var manifestWasWritten = false
        do {
            // Recovery evidence must be durable before the first file mutation.
            try manifestStore.write(manifest)
            manifestWasWritten = true
            phase = .moveFiles
            try moveToTrash(
                relativePaths: plan.relativePaths,
                operationID: operationID,
                location: location,
                fileClient: fileClient,
                moved: &movedPaths
            )
            phase = .commitCatalog
            try commitTrash(
                plan,
                operationID: operationID,
                targetKind: targetKind
            )
            return operationID
        } catch {
            modelContext.rollback()
            throw compensateFailedTrash(
                primary: error,
                context: TrashCompensationContext(
                    operationID: operationID,
                    phase: phase,
                    manifestWasWritten: manifestWasWritten,
                    movedPaths: movedPaths,
                    location: location
                ),
                fileClient: fileClient
            )
        }
    }

    func trashOperations() throws -> [LibraryTrashProjection] {
        let records = try modelContext.fetch(
            FetchDescriptor<TrashOperationRecord>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
        let decoder = JSONDecoder()
        return try records.map { record in
            do {
                let ids = try decoder.decode(
                    [UUID].self,
                    from: record.targetIDsData
                )
                let paths = try decoder.decode(
                    [String].self,
                    from: record.originalRelativePathsData
                )
                return LibraryTrashProjection(
                    id: record.id,
                    targetKind: record.targetKind,
                    targetIDs: ids,
                    relativePaths: paths,
                    createdAt: record.createdAt
                )
            } catch {
                throw LibraryTrashError.invalidManifest
            }
        }
    }

    func emptyTrash(
        operationIDs: Set<UUID>? = nil,
        location: ManagedLibraryLocation,
        fileClient: TrashFileClient = .live
    ) throws {
        let records = try modelContext.fetch(
            FetchDescriptor<TrashOperationRecord>()
        ).filter {
            operationIDs?.contains($0.id) ?? true
        }
        // Commit metadata first. If that save fails, no permanent file deletion
        // has happened and SwiftData can roll back the entire request.
        let operationIDs = records.map(\.id)
        for record in records {
            modelContext.delete(record)
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        var cleanupFailures: [(operationID: UUID, message: String)] = []
        for operationID in operationIDs {
            do {
                try removeTrashOperationDirectory(
                    operationID: operationID,
                    location: location,
                    fileClient: fileClient
                )
            } catch {
                cleanupFailures.append(
                    (operationID, error.localizedDescription)
                )
            }
        }
        if let firstFailure = cleanupFailures.first {
            throw LibraryTrashTransactionError(
                operationID: firstFailure.operationID,
                phase: .cleanup,
                primaryFailure: firstFailure.message,
                compensationFailures: cleanupFailures.dropFirst().map {
                    "\($0.operationID.uuidString): \($0.message)"
                },
                recoveryDirectory: trashOperationDirectory(
                    operationID: firstFailure.operationID,
                    location: location
                )
            )
        }
    }
}

private extension LibraryRepository {
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

        let allCredits = try creditRecords(
            trackIDs: Set(creditedTracks.map(\.id))
        )
        let creditsByTrackID = Dictionary(grouping: allCredits, by: \.trackID)
        var deletedTracks: [TrackRecord] = []
        var retainedTracks: [TrackRecord] = []
        for track in creditedTracks {
            let credits = creditsByTrackID[track.id] ?? []
            if credits.filter({ $0.artistID != id }).isEmpty {
                deletedTracks.append(track)
            } else {
                retainedTracks.append(track)
            }
        }
        let deletedTrackIDs = Set(deletedTracks.map(\.id))
        let retainedTrackIDs = Set(retainedTracks.map(\.id))
        let removedCredits = allCredits.filter {
            deletedTrackIDs.contains($0.trackID)
                || (retainedTrackIDs.contains($0.trackID) && $0.artistID == id)
        }

        var albums = relatedAlbums(deletedTracks)
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
            deletedTracks,
            credits: removedCredits
        )
        artists[targetArtist.id] = targetArtist
        let deletedArtistIDs = try Set([targetArtist.id]).union(
            emptyArtistIDs(artists, afterRemoving: deletedTrackIDs)
        )
        let artworks = try artworkRecordsForTrash(
            trackIDs: deletedTrackIDs,
            albumIDs: deletedAlbumIDs,
            artistIDs: deletedArtistIDs
        )
        return LibraryTrashPlan(
            tracks: deletedTracks,
            retainedTracks: retainedTracks,
            credits: removedCredits,
            trackIDs: deletedTrackIDs,
            albums: albums,
            artists: artists,
            deletedAlbumIDs: deletedAlbumIDs,
            deletedArtistIDs: deletedArtistIDs,
            targetArtistID: targetArtist.id,
            artworks: artworks,
            relativePaths: trashRelativePaths(
                tracks: deletedTracks,
                artworks: artworks
            )
        )
    }

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
        var artists: [UUID: ArtistRecord] = tracks.reduce(into: [:]) {
            artists, track in
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
