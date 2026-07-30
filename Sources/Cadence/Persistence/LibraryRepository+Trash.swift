import Foundation
import SwiftData

enum LibraryTrashError: Error, LocalizedError, Sendable {
    case destinationConflict
    case invalidManifest
    case missingTarget
    case unavailableLibrary

    var errorDescription: String? {
        switch self {
        case .destinationConflict:
            "A managed file already exists at the restore destination."
        case .invalidManifest:
            "The Trash operation cannot be restored safely."
        case .missingTarget:
            "The selected library item no longer exists."
        case .unavailableLibrary:
            "The managed library is unavailable."
        }
    }
}

struct LibraryTrashPlan {
    let tracks: [TrackRecord]
    let trackIDs: Set<UUID>
    let albums: [UUID: AlbumRecord]
    let artists: [UUID: ArtistRecord]
    let deletedAlbumIDs: Set<UUID>
    let deletedArtistIDs: Set<UUID>
    let artworks: [ArtworkRecord]
    let relativePaths: [String]
}

extension LibraryRepository {
    func trash(
        targetKind: TrashTargetKind,
        targetID: UUID,
        location: ManagedLibraryLocation
    ) throws -> UUID {
        let plan = try makeTrashPlan(
            kind: targetKind,
            id: targetID
        )
        let operationID = UUID()
        let manifest = try makeTrashManifest(
            plan: plan,
            operationID: operationID,
            targetKind: targetKind
        )
        let movedPaths = try moveToTrash(
            relativePaths: plan.relativePaths,
            operationID: operationID,
            location: location
        )

        do {
            try ManagedTrashManifestStore(location: location)
                .write(manifest)
            try commitTrash(
                plan,
                operationID: operationID,
                targetKind: targetKind
            )
            return operationID
        } catch {
            modelContext.rollback()
            restoreMovedPaths(movedPaths)
            removeTrashOperationDirectory(
                operationID: operationID,
                location: location
            )
            throw error
        }
    }

    func trashOperations() throws -> [LibraryTrashProjection] {
        let records = try modelContext.fetch(
            FetchDescriptor<TrashOperationRecord>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
        let decoder = JSONDecoder()
        return records.compactMap { record in
            guard
                let ids = try? decoder.decode(
                    [UUID].self,
                    from: record.targetIDsData
                ),
                let paths = try? decoder.decode(
                    [String].self,
                    from: record.originalRelativePathsData
                )
            else {
                return nil
            }
            return LibraryTrashProjection(
                id: record.id,
                targetKind: record.targetKind,
                targetIDs: ids,
                relativePaths: paths,
                createdAt: record.createdAt
            )
        }
    }

    func emptyTrash(
        operationIDs: Set<UUID>? = nil,
        location: ManagedLibraryLocation
    ) throws {
        let records = try modelContext.fetch(
            FetchDescriptor<TrashOperationRecord>()
        ).filter {
            operationIDs?.contains($0.id) ?? true
        }
        let package = ManagedLibraryPackage(location: location)
        for record in records {
            let directory = package.trashDirectoryURL.appending(
                path: record.id.uuidString,
                directoryHint: .isDirectory
            )
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}

private extension LibraryRepository {
    func makeTrashPlan(
        kind: TrashTargetKind,
        id: UUID
    ) throws -> LibraryTrashPlan {
        let tracks = try trashTargetTracks(kind: kind, id: id)
        guard !tracks.isEmpty else {
            throw LibraryTrashError.missingTarget
        }
        let trackIDs = Set(tracks.map(\.id))
        let albums = relatedAlbums(tracks)
        let artists = relatedArtists(tracks)
        let deletedAlbumIDs = emptyAlbumIDs(
            albums,
            afterRemoving: trackIDs
        )
        let deletedArtistIDs = emptyArtistIDs(
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
            trackIDs: trackIDs,
            albums: albums,
            artists: artists,
            deletedAlbumIDs: deletedAlbumIDs,
            deletedArtistIDs: deletedArtistIDs,
            artworks: artworks,
            relativePaths: trashRelativePaths(
                tracks: tracks,
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
        try modelContext.insert(
            TrashOperationRecord(
                id: operationID,
                targetKind: targetKind,
                targetIDsData: encoder.encode(Array(plan.trackIDs)),
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
        plan.tracks.forEach(modelContext.delete)
        plan.artworks.forEach(modelContext.delete)
        refreshAfterTrash(
            removedTrackIDs: plan.trackIDs,
            albums: plan.albums,
            artists: plan.artists
        )
        try modelContext.save()
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
        _ tracks: [TrackRecord]
    ) -> [UUID: ArtistRecord] {
        tracks.reduce(into: [:]) { artists, track in
            if let artist = track.artist {
                artists[artist.id] = artist
            }
        }
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
    ) -> Set<UUID> {
        Set(artists.values.compactMap { artist in
            artist.tracks.allSatisfy { trackIDs.contains($0.id) }
                ? artist.id
                : nil
        })
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

    func refreshAfterTrash(
        removedTrackIDs: Set<UUID>,
        albums: [UUID: AlbumRecord],
        artists: [UUID: ArtistRecord]
    ) {
        var removedAlbumIDs: Set<UUID> = []
        for album in albums.values {
            let remaining = album.tracks.filter {
                !removedTrackIDs.contains($0.id)
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
        for artist in artists.values {
            let remainingTracks = artist.tracks.filter {
                !removedTrackIDs.contains($0.id)
            }
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
