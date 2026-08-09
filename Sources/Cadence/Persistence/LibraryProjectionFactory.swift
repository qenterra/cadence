import Foundation
import SwiftData

private struct ProjectionArtistCredit {
    let artistID: UUID
    let displayName: String
}

enum LibraryProjectionFactory {
    static func track(
        _ track: TrackRecord,
        creditedArtistNames: [String] = []
    ) -> LibraryTrackProjection {
        let artistNames = creditedArtistNames.isEmpty
            ? [track.artist?.name ?? "Unknown Artist"]
            : creditedArtistNames
        return LibraryTrackProjection(
            id: track.id,
            title: track.title,
            artistID: track.artist?.id,
            artist: artistNames.joined(separator: ", "),
            albumID: track.album?.id,
            album: track.album?.title ?? "Unknown Album",
            duration: track.duration,
            year: track.album?.year,
            codec: track.codec,
            sampleRate: track.sampleRate,
            channelCount: track.channelCount,
            bitDepth: track.bitDepth,
            isFavorite: track.isFavorite,
            customArtworkID: track.customArtworkID,
            artworkID:
            track.customArtworkID ?? track.album?.customArtworkID,
            relativeMediaPath: track.relativeMediaPath,
            dateAdded: track.dateAdded,
            lastPlayedAt: track.lastPlayedAt,
            playCount: track.playCount,
            hasSynchronizedLyrics: track.lyrics?.parsingStatus == .valid
                && track.lyrics?.timingStatus == .synchronized
        )
    }

    static func artist(
        _ artist: ArtistRecord,
        albumCount: Int? = nil
    ) -> LibraryArtistProjection {
        LibraryArtistProjection(
            id: artist.id,
            name: artist.name,
            albumCount: albumCount ?? artist.albumCount,
            trackCount: artist.trackCount,
            isFavorite: artist.isFavorite,
            favoriteDate: artist.favoriteDate,
            customArtworkID: artist.customArtworkID
        )
    }

    static func album(
        _ album: AlbumRecord,
        creditedArtistNames: [String] = []
    ) -> LibraryAlbumProjection {
        let artistNames = creditedArtistNames.isEmpty
            ? [album.artist?.name ?? "Unknown Artist"]
            : creditedArtistNames
        return LibraryAlbumProjection(
            id: album.id,
            title: album.title,
            artistID: album.artist?.id,
            artist: artistNames.joined(separator: ", "),
            year: album.year,
            dateAdded: album.dateAdded,
            trackCount: album.trackCount,
            totalDuration: album.totalDuration,
            isFavorite: album.isFavorite,
            favoriteDate: album.favoriteDate,
            customArtworkID: album.customArtworkID
        )
    }

    static func tag(
        _ tag: TagRecord
    ) -> LibraryTagProjection {
        LibraryTagProjection(
            id: tag.id,
            displayPath: tag.displayPath,
            groupPath: tag.groupPath
        )
    }

    static func playback(
        _ track: TrackRecord,
        creditedArtistNames: [String] = []
    ) -> PlaybackTrack {
        let artistNames = creditedArtistNames.isEmpty
            ? [track.artist?.name ?? "Unknown Artist"]
            : creditedArtistNames
        return PlaybackTrack(
            id: track.id,
            title: track.title,
            artistID: track.artist?.id,
            artist: artistNames.joined(separator: ", "),
            albumID: track.album?.id,
            album: track.album?.title ?? "Unknown Album",
            duration: track.duration,
            codec: track.codec,
            container: track.container,
            sampleRate: track.sampleRate,
            channelCount: track.channelCount,
            bitrate: track.bitrate,
            bitDepth: track.bitDepth,
            spatialFormat: track.spatialFormat,
            relativeMediaPath: track.relativeMediaPath,
            lyricRelativePath: track.lyrics?.relativePath,
            artworkID: track.customArtworkID ?? track.album?.customArtworkID,
            replayGainTrackGain: track.replayGainTrackGain,
            replayGainTrackPeak: track.replayGainTrackPeak,
            year: track.album?.year,
            discNumber: track.discNumber,
            trackNumber: track.trackNumber
        )
    }
}

extension LibraryRepository {
    func trackProjection(
        _ track: TrackRecord
    ) throws -> LibraryTrackProjection {
        try trackProjections([track]).first
            ?? LibraryProjectionFactory.track(track)
    }

    func trackProjections(
        _ tracks: [TrackRecord]
    ) throws -> [LibraryTrackProjection] {
        let artistsByTrackID = try creditedArtistsByTrackID(
            tracks.map(\.id)
        )
        return tracks.map {
            LibraryProjectionFactory.track(
                $0,
                creditedArtistNames: artistsByTrackID[$0.id]?.map(\.displayName)
                    ?? []
            )
        }
    }

    func playbackProjections(
        _ tracks: [TrackRecord]
    ) throws -> [PlaybackTrack] {
        let artistsByTrackID = try creditedArtistsByTrackID(
            tracks.map(\.id)
        )
        return tracks.map {
            LibraryProjectionFactory.playback(
                $0,
                creditedArtistNames: artistsByTrackID[$0.id]?.map(\.displayName)
                    ?? []
            )
        }
    }

    func albumProjection(
        _ album: AlbumRecord
    ) throws -> LibraryAlbumProjection {
        try albumProjections([album]).first
            ?? LibraryProjectionFactory.album(album)
    }

    func albumProjections(
        _ albums: [AlbumRecord]
    ) throws -> [LibraryAlbumProjection] {
        let tracks = albums.flatMap(\.tracks)
        let artistsByTrackID = try creditedArtistsByTrackID(
            tracks.map(\.id)
        )
        return albums.map { album in
            LibraryProjectionFactory.album(
                album,
                creditedArtistNames: albumArtistNames(
                    album,
                    artistsByTrackID: artistsByTrackID
                )
            )
        }
    }

    func artistProjection(
        _ artist: ArtistRecord
    ) throws -> LibraryArtistProjection {
        try LibraryProjectionFactory.artist(
            artist,
            albumCount: participatingAlbumIDs(
                artistID: artist.id
            ).count
        )
    }

    func artistProjections(
        _ artists: [ArtistRecord]
    ) throws -> [LibraryArtistProjection] {
        let artistIDs = artists.map(\.id)
        var albumIDsByArtistID = Dictionary(
            uniqueKeysWithValues: artists.map { artist in
                (
                    artist.id,
                    Set(
                        artist.albums.map(\.id)
                            + artist.tracks.compactMap { $0.album?.id }
                    )
                )
            }
        )
        var credits: [TrackArtistCreditRecord] = []
        for artistIDChunk in projectionChunks(artistIDs) {
            let predicate = #Predicate<TrackArtistCreditRecord> {
                artistIDChunk.contains($0.artistID)
            }
            try credits.append(
                contentsOf: modelContext.fetch(
                    FetchDescriptor(predicate: predicate)
                )
            )
        }
        var albumIDByTrackID: [UUID: UUID] = [:]
        for trackIDChunk in projectionChunks(credits.map(\.trackID)) {
            let predicate = #Predicate<TrackRecord> {
                trackIDChunk.contains($0.id)
            }
            for track in try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ) {
                albumIDByTrackID[track.id] = track.album?.id
            }
        }
        for credit in credits {
            guard let albumID = albumIDByTrackID[credit.trackID] else {
                continue
            }
            albumIDsByArtistID[credit.artistID, default: []].insert(albumID)
        }
        return artists.map {
            LibraryProjectionFactory.artist(
                $0,
                albumCount: albumIDsByArtistID[$0.id]?.count ?? 0
            )
        }
    }

    func trackPage(
        records: [TrackRecord],
        limit: Int,
        sortValue: KeyPath<TrackRecord, String>,
        identity: KeyPath<TrackRecord, String>
    ) throws -> LibraryPage<LibraryTrackProjection> {
        let hasMore = records.count > limit
        let pageRecords = Array(records.prefix(limit))
        return try LibraryPage(
            items: trackProjections(pageRecords),
            nextCursor: hasMore
                ? pageRecords.last.map {
                    LibraryPageCursor(
                        sortValue: $0[keyPath: sortValue],
                        identity: $0[keyPath: identity]
                    )
                }
                : nil
        )
    }

    func albumPage(
        records: [AlbumRecord],
        limit: Int,
        sortValue: KeyPath<AlbumRecord, String>,
        identity: KeyPath<AlbumRecord, String>
    ) throws -> LibraryPage<LibraryAlbumProjection> {
        let hasMore = records.count > limit
        let pageRecords = Array(records.prefix(limit))
        return try LibraryPage(
            items: albumProjections(pageRecords),
            nextCursor: hasMore
                ? pageRecords.last.map {
                    LibraryPageCursor(
                        sortValue: $0[keyPath: sortValue],
                        identity: $0[keyPath: identity]
                    )
                }
                : nil
        )
    }

    func participatingAlbumIDs(
        artistID: UUID
    ) throws -> Set<UUID> {
        let creditPredicate = #Predicate<TrackArtistCreditRecord> {
            $0.artistID == artistID
        }
        let creditedTrackIDs = try modelContext.fetch(
            FetchDescriptor(predicate: creditPredicate)
        ).map(\.trackID)
        let primaryPredicate = #Predicate<TrackRecord> {
            $0.artist?.id == artistID
        }
        let primaryTracks = try modelContext.fetch(
            FetchDescriptor(predicate: primaryPredicate)
        )
        var albumIDs = Set(primaryTracks.compactMap { $0.album?.id })
        for trackIDChunk in projectionChunks(creditedTrackIDs) {
            let predicate = #Predicate<TrackRecord> {
                trackIDChunk.contains($0.id)
            }
            try albumIDs.formUnion(
                modelContext.fetch(
                    FetchDescriptor(predicate: predicate)
                ).compactMap { $0.album?.id }
            )
        }
        let ownerPredicate = #Predicate<AlbumRecord> {
            $0.artist?.id == artistID
        }
        try albumIDs.formUnion(
            modelContext.fetch(
                FetchDescriptor(predicate: ownerPredicate)
            ).map(\.id)
        )
        return albumIDs
    }
}

private extension LibraryRepository {
    func creditedArtistsByTrackID(
        _ trackIDs: [UUID]
    ) throws -> [UUID: [ProjectionArtistCredit]] {
        var credits: [TrackArtistCreditRecord] = []
        for trackIDChunk in projectionChunks(trackIDs) {
            let predicate = #Predicate<TrackArtistCreditRecord> {
                trackIDChunk.contains($0.trackID)
            }
            try credits.append(
                contentsOf: modelContext.fetch(
                    FetchDescriptor(predicate: predicate)
                )
            )
        }
        var artistsByID: [UUID: ArtistRecord] = [:]
        for artistIDChunk in projectionChunks(credits.map(\.artistID)) {
            let predicate = #Predicate<ArtistRecord> {
                artistIDChunk.contains($0.id)
            }
            for artist in try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ) {
                artistsByID[artist.id] = artist
            }
        }
        return Dictionary(grouping: credits, by: \.trackID).mapValues {
            let sortedCredits = $0.sorted {
                if $0.position == $1.position {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.position < $1.position
            }
            var artistIDs: Set<UUID> = []
            return sortedCredits.compactMap { credit in
                guard artistIDs.insert(credit.artistID).inserted else {
                    return nil
                }
                return ProjectionArtistCredit(
                    artistID: credit.artistID,
                    displayName: artistsByID[credit.artistID]?.name
                        ?? credit.displayArtistName
                )
            }
        }
    }

    func albumArtistNames(
        _ album: AlbumRecord,
        artistsByTrackID: [UUID: [ProjectionArtistCredit]]
    ) -> [String] {
        var artists = album.artist.map {
            [
                ProjectionArtistCredit(
                    artistID: $0.id,
                    displayName: $0.name
                ),
            ]
        } ?? []
        for track in album.tracks.sorted(by: Self.albumTrackOrder) {
            let trackArtists = artistsByTrackID[track.id]
                ?? track.artist.map {
                    [
                        ProjectionArtistCredit(
                            artistID: $0.id,
                            displayName: $0.name
                        ),
                    ]
                }
                ?? []
            artists.append(contentsOf: trackArtists)
        }
        var artistIDs: Set<UUID> = []
        return artists.compactMap { artist in
            guard artistIDs.insert(artist.artistID).inserted else {
                return nil
            }
            return artist.displayName
        }
    }

    func projectionChunks(
        _ values: [UUID]
    ) -> [[UUID]] {
        let uniqueValues = Array(values)
        let maximumCount = 100
        guard !uniqueValues.isEmpty else {
            return []
        }
        return stride(
            from: 0,
            to: uniqueValues.count,
            by: maximumCount
        ).map {
            Array(uniqueValues[$0 ..< min($0 + maximumCount, uniqueValues.count)])
        }
    }
}
