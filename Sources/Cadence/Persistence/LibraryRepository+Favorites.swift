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
        return LibraryProjectionFactory.track(record)
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
