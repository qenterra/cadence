import Foundation
import SwiftData

extension LibraryRepository {
    func tracksWindow(
        query: LibraryTrackQuery,
        offset: Int,
        limit: Int
    ) throws -> [LibraryTrackProjection] {
        let boundedOffset = max(offset, 0)
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        if query.sort.field == .album || query.sort.field == .year {
            let records = try relationshipSortedRecords(query: query)
            let pageRecords = records.dropFirst(boundedOffset)
                .prefix(boundedLimit)
            return try trackProjections(Array(pageRecords))
        }
        let sortBy = switch query.sort.field {
        case .song:
            titleSortDescriptors(
                isAscending: query.sort.direction == .ascending
            )
        case .album, .year, .duration:
            scalarSortDescriptors(query.sort)
        }
        var descriptor = trackDescriptor(
            scope: query.scope,
            search: query.search,
            sortBy: sortBy
        )
        descriptor.fetchOffset = boundedOffset
        descriptor.fetchLimit = boundedLimit
        return try trackProjections(modelContext.fetch(descriptor))
    }

    func tracksPage(
        query: LibraryTrackQuery,
        after cursor: LibraryPageCursor? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryTrackProjection> {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)

        if case let .artist(artistID) = query.scope {
            return try creditedTracksPage(
                artistID: artistID,
                query: query,
                after: cursor,
                limit: boundedLimit
            )
        }

        if query.sort.field == .song {
            return try titleSortedTracksPage(
                query: query,
                after: cursor,
                limit: boundedLimit
            )
        }

        if query.sort.field == .album || query.sort.field == .year {
            return try relationshipSortedTracksPage(
                query: query,
                after: cursor,
                limit: boundedLimit
            )
        }

        return try offsetSortedTracksPage(
            query: query,
            after: cursor,
            limit: boundedLimit,
            sortBy: scalarSortDescriptors(query.sort)
        )
    }
}

private extension LibraryRepository {
    func creditedTracksPage(
        artistID: UUID,
        query: LibraryTrackQuery,
        after cursor: LibraryPageCursor?,
        limit: Int
    ) throws -> LibraryPage<LibraryTrackProjection> {
        let trackIDs = try creditedTrackIDs(artistID: artistID)
        guard !trackIDs.isEmpty else {
            return LibraryPage(items: [], nextCursor: nil)
        }

        if query.sort.field == .song {
            var descriptor = creditedTitleDescriptor(
                trackIDs: trackIDs,
                query: query,
                after: cursor
            )
            descriptor.fetchLimit = limit + 1
            return try trackPage(
                records: modelContext.fetch(descriptor),
                limit: limit,
                sortValue: \.normalizedTitle,
                identity: \.sortIdentity
            )
        }

        let offset = cursor?.offset ?? 0
        var descriptor = creditedTracksDescriptor(
            trackIDs: trackIDs,
            query: query
        )
        if query.sort.field == .album || query.sort.field == .year {
            return try slicedOffsetPage(
                records: relationshipSortedRecords(
                    descriptor: descriptor,
                    sort: query.sort
                ),
                offset: offset,
                limit: limit
            )
        }
        descriptor.sortBy = scalarSortDescriptors(query.sort)
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit + 1
        return try offsetPage(
            records: modelContext.fetch(descriptor),
            offset: offset,
            limit: limit
        )
    }

    func creditedTracksDescriptor(
        trackIDs: [UUID],
        query: LibraryTrackQuery
    ) -> FetchDescriptor<TrackRecord> {
        let hasSearch = !query.search.isEmpty
        let search = query.search
        let predicate = #Predicate<TrackRecord> { record in
            trackIDs.contains(record.id)
                && (!hasSearch || record.normalizedTitle.contains(search))
        }
        return FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\TrackRecord.sortIdentity)]
        )
    }

    func creditedTrackIDs(artistID: UUID) throws -> [UUID] {
        let creditPredicate = #Predicate<TrackArtistCreditRecord> { credit in
            credit.artistID == artistID
        }
        let credited = try modelContext.fetch(
            FetchDescriptor(predicate: creditPredicate)
        ).map(\.trackID)
        let primaryPredicate = #Predicate<TrackRecord> { track in
            track.artist?.id == artistID
        }
        let primary = try modelContext.fetch(
            FetchDescriptor(predicate: primaryPredicate)
        ).map(\.id)
        return Array(Set(credited + primary))
    }

    func creditedTitleDescriptor(
        trackIDs: [UUID],
        query: LibraryTrackQuery,
        after cursor: LibraryPageCursor?
    ) -> FetchDescriptor<TrackRecord> {
        let hasSearch = !query.search.isEmpty
        let search = query.search
        let hasCursor = cursor != nil
        let cursorValue = cursor?.sortValue ?? ""
        let cursorIdentity = cursor?.identity ?? ""
        let isAscending = query.sort.direction == .ascending
        let predicate = #Predicate<TrackRecord> { record in
            trackIDs.contains(record.id)
                && (!hasSearch || record.normalizedTitle.contains(search))
                && (
                    !hasCursor
                        || isAscending && (
                            record.normalizedTitle > cursorValue
                                || record.normalizedTitle == cursorValue
                                && record.sortIdentity > cursorIdentity
                        )
                        || !isAscending && (
                            record.normalizedTitle < cursorValue
                                || record.normalizedTitle == cursorValue
                                && record.sortIdentity > cursorIdentity
                        )
                )
        }
        return FetchDescriptor(
            predicate: predicate,
            sortBy: titleSortDescriptors(isAscending: isAscending)
        )
    }

    func titleSortedTracksPage(
        query: LibraryTrackQuery,
        after cursor: LibraryPageCursor?,
        limit: Int
    ) throws -> LibraryPage<LibraryTrackProjection> {
        var descriptor = titleSortedDescriptor(
            query: query,
            after: cursor
        )
        descriptor.fetchLimit = limit + 1
        return try trackPage(
            records: modelContext.fetch(descriptor),
            limit: limit,
            sortValue: \.normalizedTitle,
            identity: \.sortIdentity
        )
    }

    func offsetSortedTracksPage(
        query: LibraryTrackQuery,
        after cursor: LibraryPageCursor?,
        limit: Int,
        sortBy: [SortDescriptor<TrackRecord>]
    ) throws -> LibraryPage<LibraryTrackProjection> {
        let offset = cursor?.offset ?? 0
        var descriptor = trackDescriptor(
            scope: query.scope,
            search: query.search,
            sortBy: sortBy
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit + 1
        let records = try modelContext.fetch(descriptor)
        return try offsetPage(
            records: records,
            offset: offset,
            limit: limit
        )
    }

    func relationshipSortedTracksPage(
        query: LibraryTrackQuery,
        after cursor: LibraryPageCursor?,
        limit: Int
    ) throws -> LibraryPage<LibraryTrackProjection> {
        try slicedOffsetPage(
            records: relationshipSortedRecords(query: query),
            offset: cursor?.offset ?? 0,
            limit: limit
        )
    }

    func relationshipSortedRecords(
        query: LibraryTrackQuery
    ) throws -> [TrackRecord] {
        let descriptor = trackDescriptor(
            scope: query.scope,
            search: query.search,
            sortBy: [SortDescriptor(\TrackRecord.sortIdentity)]
        )
        return try relationshipSortedRecords(
            descriptor: descriptor,
            sort: query.sort
        )
    }

    func relationshipSortedRecords(
        descriptor input: FetchDescriptor<TrackRecord>,
        sort: LibraryTrackSort
    ) throws -> [TrackRecord] {
        var descriptor = input
        descriptor.relationshipKeyPathsForPrefetching = [\TrackRecord.album]
        return try modelContext.fetch(descriptor).sorted {
            Self.relationshipTrackOrder(
                lhs: $0,
                rhs: $1,
                sort: sort
            )
        }
    }

    func slicedOffsetPage(
        records: [TrackRecord],
        offset: Int,
        limit: Int
    ) throws -> LibraryPage<LibraryTrackProjection> {
        let candidates = records.dropFirst(offset).prefix(limit + 1)
        return try offsetPage(
            records: Array(candidates),
            offset: offset,
            limit: limit
        )
    }

    func offsetPage(
        records: [TrackRecord],
        offset: Int,
        limit: Int
    ) throws -> LibraryPage<LibraryTrackProjection> {
        let pageRecords = Array(records.prefix(limit))
        return try LibraryPage(
            items: trackProjections(pageRecords),
            nextCursor: records.count > limit
                ? .offset(offset + pageRecords.count)
                : nil
        )
    }
}
