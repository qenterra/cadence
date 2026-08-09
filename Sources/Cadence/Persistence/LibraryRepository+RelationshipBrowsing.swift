import Foundation
import SwiftData

extension LibraryRepository {
    func artistReleaseSections(
        artistID: UUID
    ) throws -> ArtistReleaseSections {
        try ArtistReleaseSections.build(
            artistID: artistID,
            releases: albums(artistID: artistID)
        )
    }

    func albums(
        artistID: UUID,
        limit: Int = maximumPageSize
    ) throws -> [LibraryAlbumProjection] {
        var albums: [LibraryAlbumProjection] = []
        var cursor: LibraryPageCursor?
        repeat {
            let page = try albumsPage(
                artistID: artistID,
                after: cursor,
                limit: limit
            )
            albums.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return albums
    }

    func albumsPage(
        artistID: UUID,
        after cursor: LibraryPageCursor? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryAlbumProjection> {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        let albumIDs = try Array(
            participatingAlbumIDs(artistID: artistID)
        )
        guard !albumIDs.isEmpty else {
            return LibraryPage(items: [], nextCursor: nil)
        }
        var descriptor = albumDescriptor(
            albumIDs: albumIDs,
            after: cursor
        )
        descriptor.fetchLimit = boundedLimit + 1
        return try albumPage(
            records: modelContext.fetch(descriptor),
            limit: boundedLimit,
            sortValue: \.normalizedTitle,
            identity: \.sortIdentity
        )
    }
}

private extension LibraryRepository {
    func albumDescriptor(
        albumIDs: [UUID],
        after cursor: LibraryPageCursor?
    ) -> FetchDescriptor<AlbumRecord> {
        let sortBy = [
            SortDescriptor(\AlbumRecord.normalizedTitle),
            SortDescriptor(\AlbumRecord.sortIdentity),
        ]
        guard let cursor else {
            let predicate = #Predicate<AlbumRecord> {
                albumIDs.contains($0.id)
            }
            return FetchDescriptor(
                predicate: predicate,
                sortBy: sortBy
            )
        }

        let cursorValue = cursor.sortValue
        let cursorIdentity = cursor.identity
        let predicate = #Predicate<AlbumRecord> {
            albumIDs.contains($0.id)
                && (
                    $0.normalizedTitle > cursorValue
                        || (
                            $0.normalizedTitle == cursorValue
                                && $0.sortIdentity > cursorIdentity
                        )
                )
        }
        return FetchDescriptor(
            predicate: predicate,
            sortBy: sortBy
        )
    }
}
