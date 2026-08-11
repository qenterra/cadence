import Foundation
import SwiftData

enum LibraryFavoriteMutationError: LocalizedError {
    case trackNotFound
    case albumNotFound
    case artistNotFound
    case unavailableLibrary

    var errorDescription: String? {
        switch self {
        case .trackNotFound:
            "The track is no longer in the library."
        case .albumNotFound:
            "The album is no longer in the library."
        case .artistNotFound:
            "The artist is no longer in the library."
        case .unavailableLibrary:
            "The managed library is unavailable."
        }
    }
}

extension LibraryRepository {
    func favoriteTracksPage(
        after cursor: LibraryPageCursor? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryTrackProjection> {
        try tracksPage(
            query: LibraryTrackQuery(scope: .favorites),
            after: cursor,
            limit: limit
        )
    }

    func favoriteAlbumsPage(
        after cursor: LibraryPageCursor? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryAlbumProjection> {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        let sortBy = [
            SortDescriptor(\AlbumRecord.normalizedTitle),
            SortDescriptor(\AlbumRecord.sortIdentity),
        ]
        let descriptor: FetchDescriptor<AlbumRecord>
        if let cursor {
            let cursorValue = cursor.sortValue
            let cursorIdentity = cursor.identity
            let predicate = #Predicate<AlbumRecord> { record in
                record.isFavorite
                    && (
                        record.normalizedTitle > cursorValue
                            || record.normalizedTitle == cursorValue
                            && record.sortIdentity > cursorIdentity
                    )
            }
            descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
        } else {
            let predicate = #Predicate<AlbumRecord> { $0.isFavorite }
            descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
        }
        var boundedDescriptor = descriptor
        boundedDescriptor.fetchLimit = boundedLimit + 1
        return try albumPage(
            records: modelContext.fetch(boundedDescriptor),
            limit: boundedLimit,
            sortValue: \.normalizedTitle,
            identity: \.sortIdentity
        )
    }

    func favoriteArtistsPage(
        after cursor: LibraryPageCursor? = nil,
        limit: Int = maximumPageSize
    ) throws -> LibraryPage<LibraryArtistProjection> {
        let boundedLimit = min(max(limit, 1), Self.maximumPageSize)
        let sortBy = [
            SortDescriptor(\ArtistRecord.normalizedName),
            SortDescriptor(\ArtistRecord.sortIdentity),
        ]
        let descriptor: FetchDescriptor<ArtistRecord>
        if let cursor {
            let cursorValue = cursor.sortValue
            let cursorIdentity = cursor.identity
            let predicate = #Predicate<ArtistRecord> { record in
                record.isFavorite
                    && (
                        record.normalizedName > cursorValue
                            || record.normalizedName == cursorValue
                            && record.sortIdentity > cursorIdentity
                    )
            }
            descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
        } else {
            let predicate = #Predicate<ArtistRecord> { $0.isFavorite }
            descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
        }
        var boundedDescriptor = descriptor
        boundedDescriptor.fetchLimit = boundedLimit + 1
        let records = try modelContext.fetch(boundedDescriptor)
        let pageRecords = Array(records.prefix(boundedLimit))
        return try LibraryPage(
            items: artistProjections(pageRecords),
            nextCursor: records.count > boundedLimit
                ? pageRecords.last.map {
                    LibraryPageCursor(
                        sortValue: $0.normalizedName,
                        identity: $0.sortIdentity
                    )
                }
                : nil
        )
    }

    func favoriteTrackIDs() throws -> [UUID] {
        let predicate = #Predicate<TrackRecord> { $0.isFavorite }
        return try modelContext.fetch(
            FetchDescriptor(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\TrackRecord.normalizedTitle),
                    SortDescriptor(\TrackRecord.sortIdentity),
                ]
            )
        ).map(\.id)
    }

    func setTrackFavorite(
        id: UUID,
        isFavorite: Bool
    ) throws -> LibraryTrackProjection {
        let predicate = #Predicate<TrackRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw LibraryFavoriteMutationError.trackNotFound
        }
        record.isFavorite = isFavorite
        try modelContext.save()
        return try trackProjection(record)
    }

    func setAlbumFavorite(
        id: UUID,
        isFavorite: Bool,
        at date: Date = .now
    ) throws -> LibraryAlbumProjection {
        let predicate = #Predicate<AlbumRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw LibraryFavoriteMutationError.albumNotFound
        }
        record.isFavorite = isFavorite
        record.favoriteDate = isFavorite ? (record.favoriteDate ?? date) : nil
        try modelContext.save()
        return try albumProjection(record)
    }

    func setArtistFavorite(
        id: UUID,
        isFavorite: Bool,
        at date: Date = .now
    ) throws -> LibraryArtistProjection {
        let predicate = #Predicate<ArtistRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw LibraryFavoriteMutationError.artistNotFound
        }
        record.isFavorite = isFavorite
        record.favoriteDate = isFavorite ? (record.favoriteDate ?? date) : nil
        try modelContext.save()
        return try artistProjection(record)
    }
}
