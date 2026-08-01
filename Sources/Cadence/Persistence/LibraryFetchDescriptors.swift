import Foundation
import SwiftData

enum LibraryFetchDescriptors {
    static func artists(
        after cursor: LibraryPageCursor?,
        search: String
    ) -> FetchDescriptor<ArtistRecord> {
        descriptor(
            after: cursor,
            search: search
        )
    }

    static func albums(
        after cursor: LibraryPageCursor?,
        search: String
    ) -> FetchDescriptor<AlbumRecord> {
        descriptor(
            after: cursor,
            search: search
        )
    }

    private static func descriptor(
        after cursor: LibraryPageCursor?,
        search: String
    ) -> FetchDescriptor<ArtistRecord> {
        let sortDescriptors = [
            SortDescriptor(\ArtistRecord.normalizedName),
            SortDescriptor(\ArtistRecord.sortIdentity),
        ]

        if let cursor, search.isEmpty {
            let cursorValue = cursor.sortValue
            let cursorIdentity = cursor.identity
            let predicate = #Predicate<ArtistRecord> { record in
                record.normalizedName > cursorValue
                    || (
                        record.normalizedName == cursorValue
                            && record.sortIdentity > cursorIdentity
                    )
            }
            return FetchDescriptor(
                predicate: predicate,
                sortBy: sortDescriptors
            )
        }

        if let cursor {
            let cursorValue = cursor.sortValue
            let cursorIdentity = cursor.identity
            let predicate = #Predicate<ArtistRecord> { record in
                record.normalizedName.contains(search)
                    && (
                        record.normalizedName > cursorValue
                            || (
                                record.normalizedName == cursorValue
                                    && record.sortIdentity > cursorIdentity
                            )
                    )
            }
            return FetchDescriptor(
                predicate: predicate,
                sortBy: sortDescriptors
            )
        }

        guard !search.isEmpty else {
            return FetchDescriptor(sortBy: sortDescriptors)
        }

        let predicate = #Predicate<ArtistRecord> { record in
            record.normalizedName.contains(search)
        }
        return FetchDescriptor(
            predicate: predicate,
            sortBy: sortDescriptors
        )
    }

    private static func descriptor(
        after cursor: LibraryPageCursor?,
        search: String
    ) -> FetchDescriptor<AlbumRecord> {
        let sortDescriptors = [
            SortDescriptor(\AlbumRecord.normalizedTitle),
            SortDescriptor(\AlbumRecord.sortIdentity),
        ]

        if let cursor, search.isEmpty {
            let cursorValue = cursor.sortValue
            let cursorIdentity = cursor.identity
            let predicate = #Predicate<AlbumRecord> { record in
                record.normalizedTitle > cursorValue
                    || (
                        record.normalizedTitle == cursorValue
                            && record.sortIdentity > cursorIdentity
                    )
            }
            return FetchDescriptor(
                predicate: predicate,
                sortBy: sortDescriptors
            )
        }

        if let cursor {
            let cursorValue = cursor.sortValue
            let cursorIdentity = cursor.identity
            let predicate = #Predicate<AlbumRecord> { record in
                record.normalizedTitle.contains(search)
                    && (
                        record.normalizedTitle > cursorValue
                            || (
                                record.normalizedTitle == cursorValue
                                    && record.sortIdentity > cursorIdentity
                            )
                    )
            }
            return FetchDescriptor(
                predicate: predicate,
                sortBy: sortDescriptors
            )
        }

        guard !search.isEmpty else {
            return FetchDescriptor(sortBy: sortDescriptors)
        }

        let predicate = #Predicate<AlbumRecord> { record in
            record.normalizedTitle.contains(search)
        }
        return FetchDescriptor(
            predicate: predicate,
            sortBy: sortDescriptors
        )
    }
}
