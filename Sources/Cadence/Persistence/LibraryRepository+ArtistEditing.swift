import Foundation
import SwiftData

extension LibraryRepository {
    func renameArtist(
        id: UUID,
        name: String
    ) throws -> LibraryArtistProjection {
        try updateArtist(
            id: id,
            name: name,
            userDescription: artistDescription(artistID: id)
        )
    }

    func updateArtist(
        id: UUID,
        name: String,
        userDescription: String?
    ) throws -> LibraryArtistProjection {
        let name = try validatedArtistName(name)
        guard let artist = try artistRecordForEditing(id: id) else {
            throw CatalogRenameError.itemUnavailable
        }
        artist.rename(to: name)
        try persistArtistDescription(
            artistID: id,
            userDescription: userDescription
        )
        try saveArtistUpdate()
        return try artistProjection(artist)
    }

    private func persistArtistDescription(
        artistID: UUID,
        userDescription: String?
    ) throws {
        let normalizedDescription = CatalogDescriptionPolicy.normalized(
            userDescription ?? ""
        )
        let predicate = #Predicate<ArtistDescriptionRecord> {
            $0.artistID == artistID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        let existing = try modelContext.fetch(descriptor).first
        if let normalizedDescription {
            if let existing {
                existing.userDescription = normalizedDescription
            } else {
                modelContext.insert(
                    ArtistDescriptionRecord(
                        artistID: artistID,
                        userDescription: normalizedDescription
                    )
                )
            }
        } else if let existing {
            modelContext.delete(existing)
        }
    }

    private func validatedArtistName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CatalogRenameError.emptyName
        }
        return trimmed
    }

    private func artistRecordForEditing(id: UUID) throws -> ArtistRecord? {
        let predicate = #Predicate<ArtistRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func saveArtistUpdate() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
