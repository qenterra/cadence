import Foundation
import SwiftData

extension LibraryRepository {
    func tracksPage(
        query: LibraryTrackQuery,
        after cursor: LibraryPageCursor? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryTrackProjection> {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)

        if query.sort.field == .song {
            return try titleSortedTracksPage(
                query: query,
                after: cursor,
                limit: boundedLimit
            )
        }

        if query.sort.field == .album || query.sort.field == .year {
            return try offsetSortedTracksPage(
                query: query,
                after: cursor,
                limit: boundedLimit,
                sortBy: relationshipSortDescriptors(query.sort)
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
        return try LibraryPageBuilder.page(
            records: modelContext.fetch(descriptor),
            limit: limit,
            sortValue: \.normalizedTitle,
            identity: \.sortIdentity,
            projection: LibraryProjectionFactory.track
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
        return offsetPage(
            records: records,
            offset: offset,
            limit: limit
        )
    }

    func offsetPage(
        records: [TrackRecord],
        offset: Int,
        limit: Int
    ) -> LibraryPage<LibraryTrackProjection> {
        let pageRecords = Array(records.prefix(limit))
        return LibraryPage(
            items: pageRecords.map(LibraryProjectionFactory.track),
            nextCursor: records.count > limit
                ? .offset(offset + pageRecords.count)
                : nil
        )
    }

    func titleSortedDescriptor(
        query: LibraryTrackQuery,
        after cursor: LibraryPageCursor?
    ) -> FetchDescriptor<TrackRecord> {
        let isAscending = query.sort.direction == .ascending
        let sortBy = titleSortDescriptors(isAscending: isAscending)

        switch query.scope {
        case .all:
            return allTracksTitleDescriptor(
                query: query,
                after: cursor,
                sortBy: sortBy
            )
        case let .artist(artistID):
            return artistTracksTitleDescriptor(
                artistID: artistID,
                query: query,
                after: cursor,
                sortBy: sortBy
            )
        case let .album(albumID):
            return albumTracksTitleDescriptor(
                albumID: albumID,
                query: query,
                after: cursor,
                sortBy: sortBy
            )
        }
    }

    func allTracksTitleDescriptor(
        query: LibraryTrackQuery,
        after cursor: LibraryPageCursor?,
        sortBy: [SortDescriptor<TrackRecord>]
    ) -> FetchDescriptor<TrackRecord> {
        let hasSearch = !query.search.isEmpty
        let search = query.search
        let hasCursor = cursor != nil
        let cursorValue = cursor?.sortValue ?? ""
        let cursorIdentity = cursor?.identity ?? ""
        let isAscending = query.sort.direction == .ascending
        let predicate = #Predicate<TrackRecord> { record in
            (!hasSearch || record.normalizedTitle.contains(search))
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
        return FetchDescriptor(predicate: predicate, sortBy: sortBy)
    }

    func artistTracksTitleDescriptor(
        artistID: UUID,
        query: LibraryTrackQuery,
        after cursor: LibraryPageCursor?,
        sortBy: [SortDescriptor<TrackRecord>]
    ) -> FetchDescriptor<TrackRecord> {
        let hasSearch = !query.search.isEmpty
        let search = query.search
        let hasCursor = cursor != nil
        let cursorValue = cursor?.sortValue ?? ""
        let cursorIdentity = cursor?.identity ?? ""
        let isAscending = query.sort.direction == .ascending
        let predicate = #Predicate<TrackRecord> { record in
            record.artist?.id == artistID
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
        return FetchDescriptor(predicate: predicate, sortBy: sortBy)
    }

    func albumTracksTitleDescriptor(
        albumID: UUID,
        query: LibraryTrackQuery,
        after cursor: LibraryPageCursor?,
        sortBy: [SortDescriptor<TrackRecord>]
    ) -> FetchDescriptor<TrackRecord> {
        let hasSearch = !query.search.isEmpty
        let search = query.search
        let hasCursor = cursor != nil
        let cursorValue = cursor?.sortValue ?? ""
        let cursorIdentity = cursor?.identity ?? ""
        let isAscending = query.sort.direction == .ascending
        let predicate = #Predicate<TrackRecord> { record in
            record.album?.id == albumID
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
        return FetchDescriptor(predicate: predicate, sortBy: sortBy)
    }

    func titleSortDescriptors(
        isAscending: Bool
    ) -> [SortDescriptor<TrackRecord>] {
        [
            SortDescriptor(
                \TrackRecord.normalizedTitle,
                order: isAscending ? .forward : .reverse
            ),
            SortDescriptor(\TrackRecord.sortIdentity),
        ]
    }

    func trackDescriptor(
        scope: LibraryTrackScope,
        search: String,
        sortBy: [SortDescriptor<TrackRecord>]
    ) -> FetchDescriptor<TrackRecord> {
        let hasSearch = !search.isEmpty
        switch scope {
        case .all:
            let predicate = #Predicate<TrackRecord> { record in
                !hasSearch || record.normalizedTitle.contains(search)
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortBy)
        case let .artist(artistID):
            let predicate = #Predicate<TrackRecord> { record in
                record.artist?.id == artistID
                    && (!hasSearch || record.normalizedTitle.contains(search))
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortBy)
        case let .album(albumID):
            let predicate = #Predicate<TrackRecord> { record in
                record.album?.id == albumID
                    && (!hasSearch || record.normalizedTitle.contains(search))
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortBy)
        }
    }

    func scalarSortDescriptors(
        _ sort: LibraryTrackSort
    ) -> [SortDescriptor<TrackRecord>] {
        let order: SortOrder = sort.direction == .ascending
            ? .forward
            : .reverse
        let identity = SortDescriptor(\TrackRecord.sortIdentity)
        switch sort.field {
        case .dateAdded:
            return [SortDescriptor(\TrackRecord.dateAdded, order: order), identity]
        case .playCount:
            return [SortDescriptor(\TrackRecord.playCount, order: order), identity]
        case .duration:
            return [SortDescriptor(\TrackRecord.duration, order: order), identity]
        case .song, .album, .year:
            return [SortDescriptor(\TrackRecord.normalizedTitle), identity]
        }
    }

    func relationshipSortDescriptors(
        _ sort: LibraryTrackSort
    ) -> [SortDescriptor<TrackRecord>] {
        let order: SortOrder = sort.direction == .ascending
            ? .forward
            : .reverse
        let identity = SortDescriptor(\TrackRecord.sortIdentity)
        switch sort.field {
        case .album:
            return [
                SortDescriptor(\TrackRecord.album?.normalizedTitle, order: order),
                identity,
            ]
        case .year:
            return [
                SortDescriptor(\TrackRecord.album?.year, order: order),
                identity,
            ]
        case .song, .dateAdded, .playCount, .duration:
            return scalarSortDescriptors(sort)
        }
    }
}
