import Foundation
import SwiftData

struct ManagedMetadataRepairCandidate: Sendable {
    let id: UUID
    let relativeMediaPath: String
}

struct ManagedMetadataRepairPage: Sendable {
    let items: [ManagedMetadataRepairCandidate]
    let nextCursor: String?
}

struct ManagedMetadataRepair: Sendable {
    let trackID: UUID
    let metadata: ManagedImportManifest.Metadata
    let sourceMetadata: Data
}

private struct MetadataRepairAffectedRecords {
    var artists: [UUID: ArtistRecord] = [:]
    var albums: [UUID: AlbumRecord] = [:]
}

private struct MetadataRepairContext {
    let artists: [String: ArtistRecord]
    let albums: [ManagedAlbumIdentity: AlbumRecord]
    let creditsByTrackID: [UUID: [TrackArtistCreditRecord]]
    var affected: MetadataRepairAffectedRecords
}

extension LibraryRepository {
    func metadataRepairCandidates(
        after cursor: String? = nil,
        limit: Int = 100
    ) throws -> ManagedMetadataRepairPage {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        let descriptor: FetchDescriptor<TrackRecord>

        if let cursor {
            let predicate = #Predicate<TrackRecord> { track in
                track.sourceMetadata == nil
                    && track.sortIdentity > cursor
            }
            descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\.sortIdentity)]
            )
        } else {
            let predicate = #Predicate<TrackRecord> { track in
                track.sourceMetadata == nil
            }
            descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\.sortIdentity)]
            )
        }

        var boundedDescriptor = descriptor
        boundedDescriptor.fetchLimit = boundedLimit + 1
        let records = try modelContext.fetch(boundedDescriptor)
        let pageRecords = Array(records.prefix(boundedLimit))

        return ManagedMetadataRepairPage(
            items: pageRecords.map {
                ManagedMetadataRepairCandidate(
                    id: $0.id,
                    relativeMediaPath: $0.relativeMediaPath
                )
            },
            nextCursor: records.count > boundedLimit
                ? pageRecords.last?.sortIdentity
                : nil
        )
    }

    func applyMetadataRepairs(
        _ repairs: [ManagedMetadataRepair]
    ) throws -> Int {
        guard !repairs.isEmpty else {
            return 0
        }

        let repairsByID = Dictionary(
            uniqueKeysWithValues: repairs.map { ($0.trackID, $0) }
        )
        let trackIDs = Array(repairsByID.keys)
        let trackPredicate = #Predicate<TrackRecord> { track in
            trackIDs.contains(track.id)
        }
        let tracks = try modelContext.fetch(
            FetchDescriptor(predicate: trackPredicate)
        )
        var context = try metadataRepairContext(
            repairs: repairs,
            trackIDs: trackIDs
        )

        for track in tracks {
            guard let repair = repairsByID[track.id] else {
                continue
            }
            applyMetadataRepair(repair, to: track, context: &context)
        }

        removeEmptyAlbums(
            context.affected.albums,
            affectedArtists: &context.affected.artists
        )
        try refreshRepairCounts(
            artists: context.affected.artists,
            albums: context.affected.albums
        )
        try modelContext.save()
        return tracks.count
    }

    private func applyMetadataRepair(
        _ repair: ManagedMetadataRepair,
        to track: TrackRecord,
        context: inout MetadataRepairContext
    ) {
        if let artist = track.artist {
            context.affected.artists[artist.id] = artist
        }
        if let album = track.album {
            context.affected.albums[album.id] = album
        }
        for credit in context.creditsByTrackID[track.id] ?? [] {
            modelContext.delete(credit)
        }

        let metadata = repair.metadata
        let primaryArtistKey = SearchNormalizer.normalize(
            metadata.creditArtistNames[0]
        )
        let albumArtistKey = SearchNormalizer.normalize(
            metadata.albumArtistName
        )
        let albumKey = ManagedAlbumIdentity(
            normalizedArtist: albumArtistKey,
            normalizedTitle: SearchNormalizer.normalize(metadata.album)
        )
        let artist = context.artists[primaryArtistKey]
        let album = context.albums[albumKey]

        applyMetadataValues(
            repair,
            to: track,
            artist: artist,
            album: album
        )

        for (position, name) in metadata.creditArtistNames.enumerated() {
            let key = SearchNormalizer.normalize(name)
            guard let creditedArtist = context.artists[key] else {
                continue
            }
            modelContext.insert(
                TrackArtistCreditRecord(
                    track: track,
                    artist: creditedArtist,
                    position: position,
                    displayArtistName: metadata.artist
                )
            )
            context.affected.artists[creditedArtist.id] = creditedArtist
        }

        if let artist {
            context.affected.artists[artist.id] = artist
        }
        if let album {
            album.year = album.year ?? metadata.year
            context.affected.albums[album.id] = album
        }
    }

    private func applyMetadataValues(
        _ repair: ManagedMetadataRepair,
        to track: TrackRecord,
        artist: ArtistRecord?,
        album: AlbumRecord?
    ) {
        let metadata = repair.metadata
        track.rename(to: metadata.title)
        track.trackNumber = metadata.trackNumber
        track.discNumber = metadata.discNumber
        track.duration = metadata.duration
        track.codec = metadata.codec
        track.container = metadata.container
        track.sampleRate = metadata.sampleRate
        track.channelCount = metadata.channelCount
        track.bitrate = metadata.bitrate
        track.bitDepth = metadata.bitDepth
        track.spatialFormat = metadata.spatialFormat
        track.sourceMetadata = repair.sourceMetadata
        track.artist = artist
        track.album = album
    }

    private func metadataRepairContext(
        repairs: [ManagedMetadataRepair],
        trackIDs: [UUID]
    ) throws -> MetadataRepairContext {
        let creditPredicate = #Predicate<TrackArtistCreditRecord> { credit in
            trackIDs.contains(credit.trackID)
        }
        let credits = try modelContext.fetch(
            FetchDescriptor(predicate: creditPredicate)
        )
        let existingArtistIDs = Array(Set(credits.map(\.artistID)))
        let existingArtists = try modelContext.fetch(
            FetchDescriptor<ArtistRecord>(
                predicate: #Predicate { existingArtistIDs.contains($0.id) }
            )
        )
        let artists = try repairArtists(for: repairs)
        var affected = MetadataRepairAffectedRecords()
        for artist in existingArtists {
            affected.artists[artist.id] = artist
        }
        return try MetadataRepairContext(
            artists: artists,
            albums: repairAlbums(for: repairs, artists: artists),
            creditsByTrackID: Dictionary(grouping: credits, by: \.trackID),
            affected: affected
        )
    }

    private func repairArtists(
        for repairs: [ManagedMetadataRepair]
    ) throws -> [String: ArtistRecord] {
        var displayNamesByKey: [String: String] = [:]
        for repair in repairs {
            let names = repair.metadata.creditArtistNames
                + [repair.metadata.albumArtistName]
            for name in names {
                let key = SearchNormalizer.normalize(name)
                displayNamesByKey[key] = displayNamesByKey[key] ?? name
            }
        }
        let names = Array(displayNamesByKey.keys)
        let predicate = #Predicate<ArtistRecord> { artist in
            names.contains(artist.normalizedName)
        }
        let existing = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
        var artists = Dictionary(
            uniqueKeysWithValues: existing.map {
                ($0.normalizedName, $0)
            }
        )

        for (key, name) in displayNamesByKey {
            guard artists[key] == nil else {
                continue
            }
            let artist = ArtistRecord(name: name)
            modelContext.insert(artist)
            artists[key] = artist
        }
        return artists
    }

    private func repairAlbums(
        for repairs: [ManagedMetadataRepair],
        artists: [String: ArtistRecord]
    ) throws -> [ManagedAlbumIdentity: AlbumRecord] {
        let titles = Array(
            Set(
                repairs.map {
                    SearchNormalizer.normalize($0.metadata.album)
                }
            )
        )
        let predicate = #Predicate<AlbumRecord> { album in
            titles.contains(album.normalizedTitle)
        }
        let existing = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
        var albums: [ManagedAlbumIdentity: AlbumRecord] = [:]

        for album in existing {
            guard let artistName = album.artist?.normalizedName else {
                continue
            }
            albums[
                ManagedAlbumIdentity(
                    normalizedArtist: artistName,
                    normalizedTitle: album.normalizedTitle
                )
            ] = album
        }

        for repair in repairs {
            let metadata = repair.metadata
            let artistKey = SearchNormalizer.normalize(
                metadata.albumArtistName
            )
            let identity = ManagedAlbumIdentity(
                normalizedArtist: artistKey,
                normalizedTitle: SearchNormalizer.normalize(metadata.album)
            )
            guard albums[identity] == nil else {
                continue
            }
            let album = AlbumRecord(
                title: metadata.album,
                artist: artists[artistKey],
                year: metadata.year
            )
            modelContext.insert(album)
            albums[identity] = album
        }
        return albums
    }

    private func removeEmptyAlbums(
        _ albums: [UUID: AlbumRecord],
        affectedArtists: inout [UUID: ArtistRecord]
    ) {
        for album in albums.values where album.tracks.isEmpty {
            if let artist = album.artist {
                affectedArtists[artist.id] = artist
            }
            modelContext.delete(album)
        }
    }

    private func refreshRepairCounts(
        artists: [UUID: ArtistRecord],
        albums: [UUID: AlbumRecord]
    ) throws {
        for album in albums.values where !album.tracks.isEmpty {
            album.trackCount = album.tracks.count
            album.totalDuration = album.tracks.reduce(0) {
                $0 + $1.duration
            }
        }

        let affectedArtistIDs = Array(artists.keys)
        let creditPredicate = #Predicate<TrackArtistCreditRecord> { credit in
            affectedArtistIDs.contains(credit.artistID)
        }
        let credits = try modelContext.fetch(
            FetchDescriptor(predicate: creditPredicate)
        )
        let creditedTrackIDs = Dictionary(
            grouping: credits,
            by: \.artistID
        ).mapValues { Set($0.map(\.trackID)).count }

        for artist in artists.values {
            let populatedAlbums = artist.albums.filter {
                !$0.tracks.isEmpty
            }
            artist.trackCount = creditedTrackIDs[artist.id] ?? 0
            artist.albumCount = populatedAlbums.count
            if artist.trackCount == 0, populatedAlbums.isEmpty {
                modelContext.delete(artist)
            }
        }
    }
}
