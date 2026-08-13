import Foundation
import SwiftData

enum PlaylistRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case playlistNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .playlistNotFound:
            "The playlist is no longer in the library."
        }
    }
}

extension LibraryRepository {
    func playlists() throws -> [LibraryPlaylistProjection] {
        let records = try modelContext.fetch(
            FetchDescriptor<PlaylistRecord>(
                sortBy: [
                    SortDescriptor(\.normalizedName),
                    SortDescriptor(\.id),
                ]
            )
        )
        let entries = try modelContext.fetch(
            FetchDescriptor<PlaylistEntryRecord>()
        )
        let trackIDs = Array(Set(entries.map(\.trackID)))
        let durations = try Dictionary(
            uniqueKeysWithValues: trackRecords(ids: trackIDs)
                .map { ($0.id, $0.duration) }
        )
        let entriesByPlaylist = Dictionary(
            grouping: entries,
            by: \.playlistID
        )

        return records.map { record in
            let playlistEntries = entriesByPlaylist[record.id] ?? []
            return LibraryPlaylistProjection(
                id: record.id,
                name: record.name,
                trackCount: playlistEntries.count,
                totalDuration: playlistEntries.reduce(0) {
                    $0 + (durations[$1.trackID] ?? 0)
                },
                modifiedAt: record.modifiedAt,
                customArtworkID: record.customArtworkID
            )
        }
    }

    func playlistTracks(
        playlistID: UUID
    ) throws -> [LibraryTrackProjection] {
        _ = try requiredPlaylistRecord(id: playlistID)
        let predicate = #Predicate<PlaylistEntryRecord> {
            $0.playlistID == playlistID
        }
        let entries = try modelContext.fetch(
            FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\.position)]
            )
        )
        let trackIDs = entries.map(\.trackID)
        let tracks = try trackRecords(ids: trackIDs)
        let tracksByID = Dictionary(
            uniqueKeysWithValues: tracks.map { ($0.id, $0) }
        )
        return try trackProjections(
            trackIDs.compactMap { tracksByID[$0] }
        )
    }

    func createPlaylist(
        name requestedName: String
    ) throws -> LibraryPlaylistProjection {
        let name = validatedPlaylistName(requestedName)
        let record = PlaylistRecord(name: name)
        modelContext.insert(record)
        try modelContext.save()
        return LibraryPlaylistProjection(
            id: record.id,
            name: record.name,
            trackCount: 0,
            totalDuration: 0,
            modifiedAt: record.modifiedAt,
            customArtworkID: record.customArtworkID
        )
    }

    func renamePlaylist(
        id: UUID,
        name requestedName: String
    ) throws {
        let playlist = try requiredPlaylistRecord(id: id)
        playlist.rename(to: validatedPlaylistName(requestedName))
        try modelContext.save()
    }

    func deletePlaylist(
        id: UUID
    ) throws {
        let playlist = try requiredPlaylistRecord(id: id)
        let entryPredicate = #Predicate<PlaylistEntryRecord> {
            $0.playlistID == id
        }
        try modelContext.delete(
            model: PlaylistEntryRecord.self,
            where: entryPredicate
        )
        modelContext.delete(playlist)
        try modelContext.save()
    }

    func addToPlaylist(
        playlistID: UUID,
        trackIDs requestedTrackIDs: [UUID]
    ) throws {
        guard !requestedTrackIDs.isEmpty else {
            return
        }
        let playlist = try requiredPlaylistRecord(id: playlistID)
        let predicate = #Predicate<PlaylistEntryRecord> {
            $0.playlistID == playlistID
        }
        let existing = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
        let liveTrackIDs = try Set(
            trackRecords(ids: requestedTrackIDs).map(\.id)
        )
        var existingIDs = Set(existing.map(\.trackID))
        var position = (existing.map(\.position).max() ?? -1) + 1
        for trackID in requestedTrackIDs
            where liveTrackIDs.contains(trackID)
            && existingIDs.insert(trackID).inserted {
            modelContext.insert(
                PlaylistEntryRecord(
                    playlistID: playlistID,
                    trackID: trackID,
                    position: position
                )
            )
            position += 1
        }
        playlist.modifiedAt = .now
        try modelContext.save()
    }

    func removeFromPlaylist(
        playlistID: UUID,
        trackIDs: [UUID]
    ) throws {
        guard !trackIDs.isEmpty else {
            return
        }
        _ = try requiredPlaylistRecord(id: playlistID)
        let predicate = #Predicate<PlaylistEntryRecord> {
            $0.playlistID == playlistID
                && trackIDs.contains($0.trackID)
        }
        try modelContext.delete(
            model: PlaylistEntryRecord.self,
            where: predicate
        )
        try normalizePlaylistPositions(playlistID: playlistID)
    }

    func reorderPlaylist(
        playlistID: UUID,
        orderedTrackIDs: [UUID]
    ) throws {
        _ = try requiredPlaylistRecord(id: playlistID)
        let predicate = #Predicate<PlaylistEntryRecord> {
            $0.playlistID == playlistID
        }
        let entries = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
        let entriesByTrackID = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.trackID, $0) }
        )
        var seen: Set<UUID> = []
        let requested = orderedTrackIDs.filter {
            entriesByTrackID[$0] != nil && seen.insert($0).inserted
        }
        let remainder = entries
            .sorted { $0.position < $1.position }
            .map(\.trackID)
            .filter { seen.insert($0).inserted }
        for (position, trackID) in (requested + remainder).enumerated() {
            entriesByTrackID[trackID]?.position = position
        }
        try modelContext.save()
    }

    func playlistTrackIDs(
        albumID: UUID
    ) throws -> [UUID] {
        let predicate = #Predicate<TrackRecord> {
            $0.album?.id == albumID
        }
        return try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
        .sorted(by: Self.albumTrackOrder)
        .map(\.id)
    }

    func playlistTrackIDs(
        artistID: UUID
    ) throws -> [UUID] {
        let predicate = #Predicate<TrackArtistCreditRecord> {
            $0.artistID == artistID
        }
        let creditedTrackIDs = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        ).map(\.trackID)
        let primaryPredicate = #Predicate<TrackRecord> {
            $0.artist?.id == artistID
        }
        let primaryTrackIDs = try modelContext.fetch(
            FetchDescriptor(predicate: primaryPredicate)
        ).map(\.id)
        let trackIDs = Array(Set(creditedTrackIDs + primaryTrackIDs))
        return try trackRecords(ids: trackIDs)
            .sorted(by: Self.artistTrackOrder)
            .map(\.id)
    }
}

private extension LibraryRepository {
    func requiredPlaylistRecord(
        id: UUID
    ) throws -> PlaylistRecord {
        guard let playlist = try playlistRecord(id: id) else {
            throw PlaylistRepositoryError.playlistNotFound(id)
        }
        return playlist
    }

    func playlistRecord(
        id: UUID
    ) throws -> PlaylistRecord? {
        let predicate = #Predicate<PlaylistRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func trackRecords(
        ids: [UUID]
    ) throws -> [TrackRecord] {
        guard !ids.isEmpty else {
            return []
        }
        let uniqueIDs = Array(Set(ids))
        let predicate = #Predicate<TrackRecord> {
            uniqueIDs.contains($0.id)
        }
        return try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
    }

    func normalizePlaylistPositions(
        playlistID: UUID
    ) throws {
        let predicate = #Predicate<PlaylistEntryRecord> {
            $0.playlistID == playlistID
        }
        let entries = try modelContext.fetch(
            FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\.position)]
            )
        )
        for (position, entry) in entries.enumerated() {
            entry.position = position
        }
        try modelContext.save()
    }

    func validatedPlaylistName(
        _ requestedName: String
    ) -> String {
        let trimmed = requestedName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? "Untitled Playlist" : trimmed
    }
}
