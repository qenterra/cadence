import Foundation
import SwiftData

extension LibraryRepository {
    func catalogCounts() throws -> LibraryCatalogCounts {
        let trashRecords = try modelContext.fetch(
            FetchDescriptor<TrashOperationRecord>()
        )
        let decoder = JSONDecoder()
        let trashedTrackCount = trashRecords.reduce(0) { count, record in
            count + (
                (try? decoder.decode(
                    [UUID].self,
                    from: record.targetIDsData
                ).count) ?? 0
            )
        }
        return try LibraryCatalogCounts(
            liveTrackCount: modelContext.fetchCount(
                FetchDescriptor<TrackRecord>()
            ),
            trashedTrackCount: trashedTrackCount
        )
    }

    func track(id: UUID) throws -> LibraryTrackProjection? {
        try trackRecord(id: id).map(LibraryProjectionFactory.track)
    }

    func artist(id: UUID) throws -> LibraryArtistProjection? {
        let predicate = #Predicate<ArtistRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(
            LibraryProjectionFactory.artist
        )
    }

    func album(id: UUID) throws -> LibraryAlbumProjection? {
        try albumRecord(id: id).map(LibraryProjectionFactory.album)
    }

    func tracks(
        albumID: UUID,
        after cursor: LibraryPageCursor? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryTrackProjection> {
        try tracksPage(
            query: LibraryTrackQuery(scope: .album(albumID)),
            after: cursor,
            limit: limit
        )
    }

    func tracks(
        artistID: UUID,
        after cursor: LibraryPageCursor? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryTrackProjection> {
        try tracksPage(
            query: LibraryTrackQuery(scope: .artist(artistID)),
            after: cursor,
            limit: limit
        )
    }

    func tagsPage(
        after cursor: LibraryPageCursor? = nil,
        search: String? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryTagProjection> {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        let normalizedSearch = SearchNormalizer.normalize(search ?? "")
        let descriptor = tagDescriptor(
            after: cursor,
            normalizedSearch: normalizedSearch
        )
        var boundedDescriptor = descriptor
        boundedDescriptor.fetchLimit = boundedLimit + 1
        let records = try modelContext.fetch(boundedDescriptor)
        let pageRecords = Array(records.prefix(boundedLimit))
        let nextCursor = records.count > boundedLimit
            ? pageRecords.last.map {
                LibraryPageCursor(
                    sortValue: $0.normalizedPath,
                    identity: $0.id.uuidString
                )
            }
            : nil

        return LibraryPage(
            items: pageRecords.map(LibraryProjectionFactory.tag),
            nextCursor: nextCursor
        )
    }

    func tracks(
        tagID: UUID,
        after cursor: LibraryPageCursor? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryTrackProjection> {
        let assignmentPredicate = #Predicate<TagAssignmentRecord> {
            $0.tagID == tagID
        }
        let assignments = try modelContext.fetch(
            FetchDescriptor(predicate: assignmentPredicate)
        )
        let directTrackIDs = Set(
            assignments
                .filter { $0.targetKind == .track }
                .map(\.targetID)
        )
        let albumIDs = assignments
            .filter { $0.targetKind == .album }
            .map(\.targetID)

        var recordsByID = try tagTrackRecordsByID(
            ids: Array(directTrackIDs)
        )
        for album in try tagAlbumRecords(ids: albumIDs) {
            for track in album.tracks {
                recordsByID[track.id] = track
            }
        }

        let exclusionPredicate = #Predicate<TagExclusionRecord> {
            $0.tagID == tagID
        }
        let excludedTrackIDs = try Set(
            modelContext.fetch(
                FetchDescriptor(predicate: exclusionPredicate)
            )
            .map(\.trackID)
        )
        let effectiveRecords = recordsByID.values.filter {
            directTrackIDs.contains($0.id)
                || !excludedTrackIDs.contains($0.id)
        }

        return relationshipPage(
            records: Array(effectiveRecords),
            after: cursor,
            limit: limit
        )
    }

    func catalogSearch(
        query: String,
        limitPerGroup: Int = 40
    ) throws -> CatalogSearchResults {
        let normalizedQuery = SearchNormalizer.normalize(query)
        guard !normalizedQuery.isEmpty else {
            return .empty
        }
        let boundedLimit = min(max(limitPerGroup, 1), Self.maximumPageSize)

        return try CatalogSearchResults(
            tracks: tracksPage(
                search: normalizedQuery,
                limit: boundedLimit
            ).items,
            albums: albumsPage(
                search: normalizedQuery,
                limit: boundedLimit
            ).items,
            artists: artistsPage(
                search: normalizedQuery,
                limit: boundedLimit
            ).items,
            tags: tagsPage(
                search: normalizedQuery,
                limit: boundedLimit
            ).items
        )
    }
}

private extension LibraryRepository {
    func tagDescriptor(
        after cursor: LibraryPageCursor?,
        normalizedSearch: String
    ) -> FetchDescriptor<TagRecord> {
        let sort = [SortDescriptor(\TagRecord.normalizedPath)]
        if let cursor, !normalizedSearch.isEmpty {
            let cursorValue = cursor.sortValue
            let predicate = #Predicate<TagRecord> {
                $0.normalizedPath.contains(normalizedSearch)
                    && $0.normalizedPath > cursorValue
            }
            return FetchDescriptor(predicate: predicate, sortBy: sort)
        }
        if let cursor {
            let cursorValue = cursor.sortValue
            let predicate = #Predicate<TagRecord> {
                $0.normalizedPath > cursorValue
            }
            return FetchDescriptor(predicate: predicate, sortBy: sort)
        }
        if !normalizedSearch.isEmpty {
            let predicate = #Predicate<TagRecord> {
                $0.normalizedPath.contains(normalizedSearch)
            }
            return FetchDescriptor(predicate: predicate, sortBy: sort)
        }
        return FetchDescriptor(sortBy: sort)
    }

    func trackRecord(id: UUID) throws -> TrackRecord? {
        let predicate = #Predicate<TrackRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func albumRecord(id: UUID) throws -> AlbumRecord? {
        let predicate = #Predicate<AlbumRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func relationshipPage(
        records: [TrackRecord],
        after cursor: LibraryPageCursor?,
        limit: Int
    ) -> LibraryPage<LibraryTrackProjection> {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        let filtered = records
            .sorted {
                if $0.normalizedTitle == $1.normalizedTitle {
                    return $0.sortIdentity < $1.sortIdentity
                }
                return $0.normalizedTitle < $1.normalizedTitle
            }
            .filter { track in
                cursor.map { cursor in
                    track.normalizedTitle > cursor.sortValue
                        || (
                            track.normalizedTitle == cursor.sortValue
                                && track.sortIdentity > cursor.identity
                        )
                } ?? true
            }
        return LibraryPageBuilder.page(
            records: Array(filtered.prefix(boundedLimit + 1)),
            limit: boundedLimit,
            sortValue: \.normalizedTitle,
            identity: \.sortIdentity,
            projection: LibraryProjectionFactory.track
        )
    }
}
