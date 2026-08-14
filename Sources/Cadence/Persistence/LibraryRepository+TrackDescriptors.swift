import Foundation
import SwiftData

extension LibraryRepository {
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
        case .favorites:
            return favoriteTracksTitleDescriptor(
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

    func favoriteTracksTitleDescriptor(
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
            record.isFavorite
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
        case .favorites:
            let predicate = #Predicate<TrackRecord> { record in
                record.isFavorite
                    && (!hasSearch || record.normalizedTitle.contains(search))
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
        case .song, .duration:
            return scalarSortDescriptors(sort)
        }
    }
}
