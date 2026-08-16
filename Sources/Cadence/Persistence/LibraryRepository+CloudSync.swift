import Foundation
import SwiftData

struct CloudMediaDescriptor: Equatable, Sendable {
    let id: UUID
    let contentHash: String
    let relativeMediaPath: String
}

enum CloudManagedAssetKind: Equatable, Sendable {
    case audio
    case artwork
    case lyrics
}

struct CloudManagedAssetDescriptor: Equatable, Sendable {
    let kind: CloudManagedAssetKind
    let contentHash: String
    let relativePath: String
}

extension LibraryRepository {
    func cloudMediaDescriptors(
        ids: [UUID]? = nil
    ) throws -> [CloudMediaDescriptor] {
        let requested = ids.map(Set.init)
        return try modelContext.fetch(FetchDescriptor<TrackRecord>())
            .compactMap { record in
                guard requested?.contains(record.id) != false else {
                    return nil
                }
                return CloudMediaDescriptor(
                    id: record.id,
                    contentHash: record.contentHash,
                    relativeMediaPath: record.relativeMediaPath
                )
            }
    }

    func cloudManagedAssetDescriptors() throws -> [CloudManagedAssetDescriptor] {
        var assets = try modelContext.fetch(FetchDescriptor<TrackRecord>()).map {
            CloudManagedAssetDescriptor(
                kind: .audio,
                contentHash: $0.contentHash,
                relativePath: $0.relativeMediaPath
            )
        }
        try assets.append(contentsOf: modelContext.fetch(FetchDescriptor<ArtworkRecord>()).map {
            CloudManagedAssetDescriptor(
                kind: .artwork,
                contentHash: $0.contentHash,
                relativePath: $0.relativeOriginalPath
            )
        })
        try assets.append(contentsOf: modelContext.fetch(FetchDescriptor<LyricRecord>()).map {
            CloudManagedAssetDescriptor(
                kind: .lyrics,
                contentHash: $0.contentHash,
                relativePath: $0.relativePath
            )
        })
        var seen = Set<String>()
        return assets.filter { seen.insert($0.contentHash).inserted }
    }

    // Keeping the schema-to-payload mapping in one ordered export makes new
    // persistent fields visible during review and prevents silent partial sync.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func exportCloudEntities() throws -> [CloudLibraryEntity] {
        let encoder = JSONEncoder()
        var entities: [CloudLibraryEntity] = []

        for record in try modelContext.fetch(FetchDescriptor<ArtistRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .artist,
                    id: record.id,
                    payload: ArtistCloudPayload(
                        name: record.name,
                        isFavorite: record.isFavorite,
                        favoriteDate: record.favoriteDate,
                        trackCount: record.trackCount,
                        albumCount: record.albumCount,
                        customArtworkID: record.customArtworkID
                    ),
                    encoder: encoder
                )
            )
        }
        for record in try modelContext.fetch(FetchDescriptor<AlbumRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .album,
                    id: record.id,
                    payload: AlbumCloudPayload(
                        title: record.title,
                        artistID: record.artist?.id,
                        year: record.year,
                        isFavorite: record.isFavorite,
                        favoriteDate: record.favoriteDate,
                        trackCount: record.trackCount,
                        totalDuration: record.totalDuration,
                        customArtworkID: record.customArtworkID
                    ),
                    encoder: encoder
                )
            )
        }
        for record in try modelContext.fetch(FetchDescriptor<TrackRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .track,
                    id: record.id,
                    payload: TrackCloudPayload(
                        originalFilename: record.originalFilename,
                        title: record.title,
                        duration: record.duration,
                        codec: record.codec,
                        container: record.container,
                        sampleRate: record.sampleRate,
                        channelCount: record.channelCount,
                        bitDepth: record.bitDepth,
                        bitrate: record.bitrate,
                        contentHash: record.contentHash,
                        relativeMediaPath: record.relativeMediaPath,
                        importSessionID: record.importSessionID,
                        artistID: record.artist?.id,
                        albumID: record.album?.id,
                        trackNumber: record.trackNumber,
                        discNumber: record.discNumber,
                        sourceFrameCount: record.sourceFrameCount,
                        lastPlayedAt: record.lastPlayedAt,
                        skipCount: record.skipCount,
                        isFavorite: record.isFavorite,
                        spatialFormatRawValue: record.spatialFormatRawValue,
                        sourceMetadata: record.sourceMetadata,
                        customArtworkID: record.customArtworkID,
                        replayGainTrackGain: record.replayGainTrackGain,
                        replayGainTrackPeak: record.replayGainTrackPeak
                    ),
                    encoder: encoder
                )
            )
        }
        for record in try modelContext.fetch(FetchDescriptor<LyricRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .lyric,
                    id: record.id,
                    payload: LyricCloudPayload(
                        trackID: record.trackID,
                        relativePath: record.relativePath,
                        textEncoding: record.textEncoding,
                        parsingStatusRawValue: record.parsingStatusRawValue,
                        timingStatusRawValue: record.timingStatusRawValue,
                        contentHash: record.contentHash,
                        modifiedAt: record.modifiedAt
                    ),
                    encoder: encoder
                )
            )
        }
        for record in try modelContext.fetch(FetchDescriptor<PlaylistRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .playlist,
                    id: record.id,
                    payload: PlaylistCloudPayload(
                        name: record.name,
                        createdAt: record.createdAt,
                        modifiedAt: record.modifiedAt,
                        customArtworkID: record.customArtworkID
                    ),
                    encoder: encoder
                )
            )
        }
        for record in try modelContext.fetch(FetchDescriptor<PlaylistEntryRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .playlistEntry,
                    id: record.id,
                    payload: PlaylistEntryCloudPayload(
                        playlistID: record.playlistID,
                        trackID: record.trackID,
                        position: record.position
                    ),
                    encoder: encoder
                )
            )
        }
        for record in try modelContext.fetch(FetchDescriptor<SmartCollectionRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .smartCollection,
                    id: record.id,
                    payload: SmartCollectionCloudPayload(
                        name: record.name,
                        ruleData: record.ruleData,
                        sortDescriptorRawValue: record.sortDescriptorRawValue,
                        playbackPreferenceRawValue: record.playbackPreferenceRawValue,
                        modifiedAt: record.modifiedAt
                    ),
                    encoder: encoder
                )
            )
        }
        for record in try modelContext.fetch(FetchDescriptor<TagRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .tag,
                    id: record.id,
                    payload: TagCloudPayload(
                        displayPath: record.displayPath,
                        groupPath: record.groupPath
                    ),
                    encoder: encoder
                )
            )
        }
        for record in try modelContext.fetch(FetchDescriptor<TagAssignmentRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .tagAssignment,
                    id: record.id,
                    payload: TagAssignmentCloudPayload(
                        targetKindRawValue: record.targetKindRawValue,
                        targetID: record.targetID,
                        tagID: record.tagID,
                        assignedAt: record.assignedAt
                    ),
                    encoder: encoder
                )
            )
        }
        for record in try modelContext.fetch(FetchDescriptor<TagExclusionRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .tagExclusion,
                    id: record.id,
                    payload: TagExclusionCloudPayload(
                        trackID: record.trackID,
                        tagID: record.tagID,
                        excludedAt: record.excludedAt
                    ),
                    encoder: encoder
                )
            )
        }
        for record in try modelContext.fetch(FetchDescriptor<ArtworkRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .artwork,
                    id: record.id,
                    payload: ArtworkCloudPayload(
                        ownerKindRawValue: record.ownerKindRawValue,
                        ownerID: record.ownerID,
                        relativeOriginalPath: record.relativeOriginalPath,
                        relativeThumbnailPath: record.relativeThumbnailPath,
                        format: record.format,
                        pixelWidth: record.pixelWidth,
                        pixelHeight: record.pixelHeight,
                        cropScale: record.cropScale,
                        normalizedOffsetX: record.normalizedOffsetX,
                        normalizedOffsetY: record.normalizedOffsetY,
                        contentHash: record.contentHash,
                        revision: record.revision
                    ),
                    encoder: encoder
                )
            )
        }
        for record in try modelContext.fetch(FetchDescriptor<TrackArtistCreditRecord>()) {
            try entities.append(
                cloudEntity(
                    kind: .artistCredit,
                    id: record.id,
                    payload: ArtistCreditCloudPayload(
                        trackID: record.trackID,
                        artistID: record.artistID,
                        position: record.position,
                        displayArtistName: record.displayArtistName
                    ),
                    encoder: encoder
                )
            )
        }
        return entities
    }

    func applyCloudRecords(
        _ records: [CloudLibraryRecord]
    ) throws {
        guard !records.isEmpty else {
            return
        }
        try applyCloudTombstones(records.filter(\.isTombstone))
        try applyCloudLiveRecords(records.filter { !$0.isTombstone })
        try modelContext.save()
    }
}

private extension LibraryRepository {
    func cloudEntity(
        kind: CloudLibraryEntityKind,
        id: UUID,
        payload: some Encodable,
        encoder: JSONEncoder
    ) throws -> CloudLibraryEntity {
        try CloudLibraryEntity(
            kind: kind,
            id: id,
            payload: encoder.encode(payload)
        )
    }

    func applyCloudTombstones(
        _ records: [CloudLibraryRecord]
    ) throws {
        for record in records {
            switch record.entityKind {
            case .artist:
                try delete(id: record.entityID, as: ArtistRecord.self)
            case .album:
                try delete(id: record.entityID, as: AlbumRecord.self)
            case .track:
                try delete(id: record.entityID, as: TrackRecord.self)
            case .lyric:
                try delete(id: record.entityID, as: LyricRecord.self)
            case .playlist:
                try delete(id: record.entityID, as: PlaylistRecord.self)
            case .playlistEntry:
                try delete(id: record.entityID, as: PlaylistEntryRecord.self)
            case .smartCollection:
                try delete(id: record.entityID, as: SmartCollectionRecord.self)
            case .tag:
                try delete(id: record.entityID, as: TagRecord.self)
            case .tagAssignment:
                try delete(id: record.entityID, as: TagAssignmentRecord.self)
            case .tagExclusion:
                try delete(id: record.entityID, as: TagExclusionRecord.self)
            case .artwork:
                try delete(id: record.entityID, as: ArtworkRecord.self)
            case .artistCredit:
                try delete(id: record.entityID, as: TrackArtistCreditRecord.self)
            }
        }
    }

    func delete<Record: PersistentModel & Identifiable>(
        id: UUID,
        as _: Record.Type
    ) throws where Record.ID == UUID {
        if let record = try modelContext.fetch(FetchDescriptor<Record>())
            .first(where: { $0.id == id }) {
            modelContext.delete(record)
        }
    }

    func applyCloudLiveRecords(
        _ records: [CloudLibraryRecord]
    ) throws {
        let decoder = JSONDecoder()
        let grouped = Dictionary(grouping: records, by: \.entityKind)
        try applyArtists(grouped[.artist] ?? [], decoder: decoder)
        try applyAlbums(grouped[.album] ?? [], decoder: decoder)
        try applyTracks(grouped[.track] ?? [], decoder: decoder)
        try applyLyrics(grouped[.lyric] ?? [], decoder: decoder)
        try applyPlaylists(grouped[.playlist] ?? [], decoder: decoder)
        try applyPlaylistEntries(grouped[.playlistEntry] ?? [], decoder: decoder)
        try applySmartCollections(grouped[.smartCollection] ?? [], decoder: decoder)
        try applyTags(grouped[.tag] ?? [], decoder: decoder)
        try applyTagAssignments(grouped[.tagAssignment] ?? [], decoder: decoder)
        try applyTagExclusions(grouped[.tagExclusion] ?? [], decoder: decoder)
        try applyArtwork(grouped[.artwork] ?? [], decoder: decoder)
        try applyArtistCredits(grouped[.artistCredit] ?? [], decoder: decoder)
    }

    func applyArtists(
        _ records: [CloudLibraryRecord],
        decoder: JSONDecoder
    ) throws {
        var existing = try dictionary(of: ArtistRecord.self)
        for record in records {
            let payload = try decoder.decode(ArtistCloudPayload.self, from: record.payload)
            let artist = existing[record.entityID] ?? ArtistRecord(
                id: record.entityID,
                name: payload.name
            )
            if existing[record.entityID] == nil {
                modelContext.insert(artist)
                existing[record.entityID] = artist
            }
            artist.rename(to: payload.name)
            artist.isFavorite = payload.isFavorite
            artist.favoriteDate = payload.favoriteDate
            artist.trackCount = payload.trackCount
            artist.albumCount = payload.albumCount
            artist.customArtworkID = payload.customArtworkID
        }
    }

    func applyAlbums(
        _ records: [CloudLibraryRecord],
        decoder: JSONDecoder
    ) throws {
        let artists = try dictionary(of: ArtistRecord.self)
        var existing = try dictionary(of: AlbumRecord.self)
        for record in records {
            let payload = try decoder.decode(AlbumCloudPayload.self, from: record.payload)
            let album = existing[record.entityID] ?? AlbumRecord(
                id: record.entityID,
                title: payload.title
            )
            if existing[record.entityID] == nil {
                modelContext.insert(album)
                existing[record.entityID] = album
            }
            album.rename(to: payload.title)
            album.artist = payload.artistID.flatMap { artists[$0] }
            album.year = payload.year
            album.isFavorite = payload.isFavorite
            album.favoriteDate = payload.favoriteDate
            album.trackCount = payload.trackCount
            album.totalDuration = payload.totalDuration
            album.customArtworkID = payload.customArtworkID
        }
    }

    func applyTracks(
        _ records: [CloudLibraryRecord],
        decoder: JSONDecoder
    ) throws {
        let artists = try dictionary(of: ArtistRecord.self)
        let albums = try dictionary(of: AlbumRecord.self)
        var existing = try dictionary(of: TrackRecord.self)
        for record in records {
            let payload = try decoder.decode(TrackCloudPayload.self, from: record.payload)
            let track = existing[record.entityID] ?? TrackRecord(
                id: record.entityID,
                originalFilename: payload.originalFilename,
                title: payload.title,
                duration: payload.duration,
                codec: payload.codec,
                container: payload.container,
                sampleRate: payload.sampleRate,
                channelCount: payload.channelCount,
                bitDepth: payload.bitDepth,
                bitrate: payload.bitrate,
                contentHash: payload.contentHash,
                relativeMediaPath: payload.relativeMediaPath,
                importSessionID: payload.importSessionID
            )
            if existing[record.entityID] == nil {
                modelContext.insert(track)
                existing[record.entityID] = track
            }
            track.originalFilename = payload.originalFilename
            track.originalExtension = URL(filePath: payload.originalFilename)
                .pathExtension.lowercased()
            track.rename(to: payload.title)
            track.duration = payload.duration
            track.codec = payload.codec
            track.container = payload.container
            track.sampleRate = payload.sampleRate
            track.channelCount = payload.channelCount
            track.bitDepth = payload.bitDepth
            track.bitrate = payload.bitrate
            track.contentHash = payload.contentHash
            track.relativeMediaPath = payload.relativeMediaPath
            track.importSessionID = payload.importSessionID
            track.artist = payload.artistID.flatMap { artists[$0] }
            track.album = payload.albumID.flatMap { albums[$0] }
            track.trackNumber = payload.trackNumber
            track.discNumber = payload.discNumber
            track.sourceFrameCount = payload.sourceFrameCount
            track.lastPlayedAt = payload.lastPlayedAt
            track.skipCount = payload.skipCount
            track.isFavorite = payload.isFavorite
            track.spatialFormatRawValue = payload.spatialFormatRawValue
            track.sourceMetadata = payload.sourceMetadata
            track.customArtworkID = payload.customArtworkID
            track.replayGainTrackGain = payload.replayGainTrackGain
            track.replayGainTrackPeak = payload.replayGainTrackPeak
        }
    }

    func applyLyrics(
        _ records: [CloudLibraryRecord],
        decoder: JSONDecoder
    ) throws {
        let tracks = try dictionary(of: TrackRecord.self)
        var existing = try dictionary(of: LyricRecord.self)
        for record in records {
            let payload = try decoder.decode(LyricCloudPayload.self, from: record.payload)
            guard let track = tracks[payload.trackID] else { continue }
            let lyric = existing[record.entityID] ?? LyricRecord(
                id: record.entityID,
                relativePath: payload.relativePath,
                textEncoding: payload.textEncoding,
                parsingStatus: StoredLyricParsingStatus(
                    rawValue: payload.parsingStatusRawValue
                ) ?? .malformed,
                contentHash: payload.contentHash,
                timingStatus: LyricTimingStatus(
                    storageRawValue: payload.timingStatusRawValue
                ) ?? .missing,
                modifiedAt: payload.modifiedAt,
                track: track
            )
            if existing[record.entityID] == nil {
                modelContext.insert(lyric)
                existing[record.entityID] = lyric
            }
            lyric.track = track
            lyric.trackID = track.id
            lyric.relativePath = payload.relativePath
            lyric.textEncoding = payload.textEncoding
            lyric.parsingStatusRawValue = payload.parsingStatusRawValue
            lyric.timingStatusRawValue = payload.timingStatusRawValue
            lyric.contentHash = payload.contentHash
            lyric.modifiedAt = payload.modifiedAt
        }
    }

    func applyPlaylists(_ records: [CloudLibraryRecord], decoder: JSONDecoder) throws {
        var existing = try dictionary(of: PlaylistRecord.self)
        for record in records {
            let payload = try decoder.decode(PlaylistCloudPayload.self, from: record.payload)
            let playlist = existing[record.entityID] ?? PlaylistRecord(
                id: record.entityID,
                name: payload.name,
                createdAt: payload.createdAt,
                modifiedAt: payload.modifiedAt
            )
            if existing[record.entityID] == nil {
                modelContext.insert(playlist)
                existing[record.entityID] = playlist
            }
            playlist.name = payload.name
            playlist.normalizedName = SearchNormalizer.normalize(payload.name)
            playlist.createdAt = payload.createdAt
            playlist.modifiedAt = payload.modifiedAt
            playlist.customArtworkID = payload.customArtworkID
        }
    }

    func applyPlaylistEntries(_ records: [CloudLibraryRecord], decoder: JSONDecoder) throws {
        var existing = try dictionary(of: PlaylistEntryRecord.self)
        for record in records {
            let payload = try decoder.decode(PlaylistEntryCloudPayload.self, from: record.payload)
            let entry = existing[record.entityID] ?? PlaylistEntryRecord(
                id: record.entityID,
                playlistID: payload.playlistID,
                trackID: payload.trackID,
                position: payload.position
            )
            if existing[record.entityID] == nil {
                modelContext.insert(entry)
                existing[record.entityID] = entry
            }
            entry.playlistID = payload.playlistID
            entry.trackID = payload.trackID
            entry.position = payload.position
        }
    }

    func applySmartCollections(_ records: [CloudLibraryRecord], decoder: JSONDecoder) throws {
        var existing = try dictionary(of: SmartCollectionRecord.self)
        for record in records {
            let payload = try decoder.decode(SmartCollectionCloudPayload.self, from: record.payload)
            let collection = existing[record.entityID] ?? SmartCollectionRecord(
                id: record.entityID,
                name: payload.name,
                ruleData: payload.ruleData,
                sortDescriptorRawValue: payload.sortDescriptorRawValue,
                playbackPreferenceRawValue: payload.playbackPreferenceRawValue,
                modifiedAt: payload.modifiedAt
            )
            if existing[record.entityID] == nil {
                modelContext.insert(collection)
                existing[record.entityID] = collection
            }
            collection.rename(to: payload.name)
            collection.ruleData = payload.ruleData
            collection.sortDescriptorRawValue = payload.sortDescriptorRawValue
            collection.playbackPreferenceRawValue = payload.playbackPreferenceRawValue
            collection.modifiedAt = payload.modifiedAt
        }
    }

    func applyTags(_ records: [CloudLibraryRecord], decoder: JSONDecoder) throws {
        var existing = try dictionary(of: TagRecord.self)
        for record in records {
            let payload = try decoder.decode(TagCloudPayload.self, from: record.payload)
            let tag = existing[record.entityID] ?? TagRecord(
                id: record.entityID,
                displayPath: payload.displayPath,
                groupPath: payload.groupPath
            )
            if existing[record.entityID] == nil {
                modelContext.insert(tag)
                existing[record.entityID] = tag
            }
            tag.displayPath = payload.displayPath
            tag.normalizedPath = SearchNormalizer.normalize(payload.displayPath)
            tag.groupPath = payload.groupPath
        }
    }

    func applyTagAssignments(_ records: [CloudLibraryRecord], decoder: JSONDecoder) throws {
        var existing = try dictionary(of: TagAssignmentRecord.self)
        for record in records {
            let payload = try decoder.decode(TagAssignmentCloudPayload.self, from: record.payload)
            let assignment = existing[record.entityID] ?? TagAssignmentRecord(
                id: record.entityID,
                targetKind: TagTargetKind(rawValue: payload.targetKindRawValue) ?? .track,
                targetID: payload.targetID,
                tagID: payload.tagID,
                assignedAt: payload.assignedAt
            )
            if existing[record.entityID] == nil {
                modelContext.insert(assignment)
                existing[record.entityID] = assignment
            }
            assignment.targetKindRawValue = payload.targetKindRawValue
            assignment.targetID = payload.targetID
            assignment.tagID = payload.tagID
            assignment.assignedAt = payload.assignedAt
        }
    }

    func applyTagExclusions(_ records: [CloudLibraryRecord], decoder: JSONDecoder) throws {
        var existing = try dictionary(of: TagExclusionRecord.self)
        for record in records {
            let payload = try decoder.decode(TagExclusionCloudPayload.self, from: record.payload)
            let exclusion = existing[record.entityID] ?? TagExclusionRecord(
                id: record.entityID,
                trackID: payload.trackID,
                tagID: payload.tagID,
                excludedAt: payload.excludedAt
            )
            if existing[record.entityID] == nil {
                modelContext.insert(exclusion)
                existing[record.entityID] = exclusion
            }
            exclusion.trackID = payload.trackID
            exclusion.tagID = payload.tagID
            exclusion.excludedAt = payload.excludedAt
        }
    }

    func applyArtwork(_ records: [CloudLibraryRecord], decoder: JSONDecoder) throws {
        var existing = try dictionary(of: ArtworkRecord.self)
        for record in records {
            let payload = try decoder.decode(ArtworkCloudPayload.self, from: record.payload)
            let artwork = existing[record.entityID] ?? ArtworkRecord(
                id: record.entityID,
                ownerKind: ArtworkOwnerKind(rawValue: payload.ownerKindRawValue) ?? .track,
                ownerID: payload.ownerID,
                relativeOriginalPath: payload.relativeOriginalPath,
                relativeThumbnailPath: payload.relativeThumbnailPath,
                format: payload.format,
                pixelWidth: payload.pixelWidth,
                pixelHeight: payload.pixelHeight,
                cropScale: payload.cropScale,
                normalizedOffsetX: payload.normalizedOffsetX,
                normalizedOffsetY: payload.normalizedOffsetY,
                contentHash: payload.contentHash,
                revision: payload.revision
            )
            if existing[record.entityID] == nil {
                modelContext.insert(artwork)
                existing[record.entityID] = artwork
            }
            artwork.ownerKindRawValue = payload.ownerKindRawValue
            artwork.ownerID = payload.ownerID
            artwork.relativeOriginalPath = payload.relativeOriginalPath
            artwork.relativeThumbnailPath = payload.relativeThumbnailPath
            artwork.format = payload.format
            artwork.pixelWidth = payload.pixelWidth
            artwork.pixelHeight = payload.pixelHeight
            artwork.cropScale = payload.cropScale
            artwork.normalizedOffsetX = payload.normalizedOffsetX
            artwork.normalizedOffsetY = payload.normalizedOffsetY
            artwork.contentHash = payload.contentHash
            artwork.revision = payload.revision
        }
    }

    func applyArtistCredits(_ records: [CloudLibraryRecord], decoder: JSONDecoder) throws {
        let tracks = try dictionary(of: TrackRecord.self)
        let artists = try dictionary(of: ArtistRecord.self)
        var existing = try dictionary(of: TrackArtistCreditRecord.self)
        for record in records {
            let payload = try decoder.decode(ArtistCreditCloudPayload.self, from: record.payload)
            guard let track = tracks[payload.trackID],
                  let artist = artists[payload.artistID] else { continue }
            let credit = existing[record.entityID] ?? TrackArtistCreditRecord(
                id: record.entityID,
                track: track,
                artist: artist,
                position: payload.position,
                displayArtistName: payload.displayArtistName
            )
            if existing[record.entityID] == nil {
                modelContext.insert(credit)
                existing[record.entityID] = credit
            }
            credit.trackID = payload.trackID
            credit.artistID = payload.artistID
            credit.position = payload.position
            credit.displayArtistName = payload.displayArtistName
        }
    }

    func dictionary<Record: PersistentModel & Identifiable>(
        of _: Record.Type
    ) throws -> [UUID: Record] where Record.ID == UUID {
        try Dictionary(
            uniqueKeysWithValues: modelContext
                .fetch(FetchDescriptor<Record>())
                .map { ($0.id, $0) }
        )
    }
}
