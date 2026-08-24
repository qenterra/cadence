import CoreGraphics
import Foundation
import SwiftData

enum ManagedArtworkEditError: Error, Equatable, LocalizedError, Sendable {
    case invalidImage
    case missingOwner
    case unavailableLibrary
    case inconsistentMetadata
    case contentHashMismatch
    case inconsistentRecovery(UUID)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The selected file is not a supported image."
        case .missingOwner:
            "The selected library item no longer exists."
        case .unavailableLibrary:
            "The managed library is unavailable."
        case .inconsistentMetadata:
            "The existing artwork metadata is inconsistent."
        case .contentHashMismatch:
            "The managed artwork file failed integrity verification."
        case let .inconsistentRecovery(operationID):
            "Artwork recovery \(operationID.uuidString) is inconsistent."
        }
    }
}

struct ManagedArtworkEditRequest: Sendable {
    let ownerKind: ArtworkOwnerKind
    let ownerID: UUID
    let data: Data
    let scale: CGFloat
    let normalizedOffset: CGSize
}

extension LibraryRepository {
    func artworkPublicationPayload(
        for effects: [ManagedArtworkPublicationEffect]
    ) throws -> LibraryArtworkPublicationPayload {
        let directTrackIDs = Set(
            effects.compactMap { effect in
                effect.ownerKind == .track ? effect.ownerID : nil
            }
        )
        let albumIDs = Set(
            effects.compactMap { effect in
                effect.ownerKind == .album ? effect.ownerID : nil
            }
        )
        let artistIDs = Set(
            effects.compactMap { effect in
                effect.ownerKind == .artist ? effect.ownerID : nil
            }
        )
        let playlistIDs = Set(
            effects.compactMap { effect in
                effect.ownerKind == .playlist ? effect.ownerID : nil
            }
        )

        var trackRows = try tracks(ids: directTrackIDs)
        for albumID in albumIDs {
            var cursor: LibraryPageCursor?
            repeat {
                let page = try tracks(albumID: albumID, after: cursor)
                trackRows.append(contentsOf: page.items)
                cursor = page.nextCursor
            } while cursor != nil
        }
        let albumRows = try albumIDs.compactMap { try album(id: $0) }
        let artistRows = try artistIDs.compactMap { try artist(id: $0) }
        let playlistRows = try playlists().filter {
            playlistIDs.contains($0.id)
        }

        return LibraryArtworkPublicationPayload(
            tracksByID: Dictionary(
                trackRows.map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            ),
            albumsByID: Dictionary(
                uniqueKeysWithValues: albumRows.map { ($0.id, $0) }
            ),
            artistsByID: Dictionary(
                uniqueKeysWithValues: artistRows.map { ($0.id, $0) }
            ),
            playlistsByID: Dictionary(
                uniqueKeysWithValues: playlistRows.map { ($0.id, $0) }
            )
        )
    }

    func artworkIDs(
        ownerKind: ArtworkOwnerKind
    ) throws -> [UUID: UUID] {
        let rawKind = ownerKind.rawValue
        let predicate = #Predicate<ArtworkRecord> {
            $0.ownerKindRawValue == rawKind
        }
        let records = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
        var ids: [UUID: UUID] = [:]
        for record in records {
            guard ids.updateValue(record.id, forKey: record.ownerID) == nil else {
                throw ManagedArtworkEditError.inconsistentMetadata
            }
        }
        return ids
    }

    func artworkEditSnapshot(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID
    ) throws -> ManagedArtworkDescriptor? {
        guard let artworkID = try ownerArtworkID(
            ownerKind: ownerKind,
            ownerID: ownerID
        ) else {
            return nil
        }
        guard let artwork = try artworkRecord(id: artworkID) else {
            throw ManagedArtworkEditError.inconsistentMetadata
        }
        return ManagedArtworkDescriptor(
            id: artwork.id,
            ownerKind: artwork.ownerKind,
            ownerID: artwork.ownerID,
            relativeOriginalPath: artwork.relativeOriginalPath,
            relativeThumbnailPath: artwork.relativeThumbnailPath,
            format: artwork.format,
            pixelWidth: artwork.pixelWidth,
            pixelHeight: artwork.pixelHeight,
            cropScale: artwork.cropScale,
            normalizedOffsetX: artwork.normalizedOffsetX,
            normalizedOffsetY: artwork.normalizedOffsetY,
            contentHash: artwork.contentHash,
            revision: artwork.revision
        )
    }

    func applyArtworkEdit(
        _ manifest: ManagedArtworkEditManifest
    ) throws {
        let manifest = try manifest.validated()
        do {
            let currentID = try ownerArtworkID(
                ownerKind: manifest.ownerKind,
                ownerID: manifest.ownerID
            )
            let previousID = manifest.previousArtwork?.id
            let desiredID = manifest.newArtwork?.id
            guard currentID == previousID || currentID == desiredID else {
                throw ManagedArtworkEditError.inconsistentMetadata
            }

            if currentID != desiredID {
                try setOwnerArtworkID(
                    desiredID,
                    ownerKind: manifest.ownerKind,
                    ownerID: manifest.ownerID
                )
            }
            if let newArtwork = manifest.newArtwork {
                try upsertArtwork(newArtwork)
            }
            if let previousID, previousID != desiredID,
               let previous = try artworkRecord(id: previousID) {
                modelContext.delete(previous)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

private extension LibraryRepository {
    func ownerArtworkID(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID
    ) throws -> UUID? {
        switch ownerKind {
        case .artist:
            let predicate = #Predicate<ArtistRecord> { $0.id == ownerID }
            guard let owner = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).first else {
                throw ManagedArtworkEditError.missingOwner
            }
            return owner.customArtworkID
        case .album:
            let predicate = #Predicate<AlbumRecord> { $0.id == ownerID }
            guard let owner = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).first else {
                throw ManagedArtworkEditError.missingOwner
            }
            return owner.customArtworkID
        case .track:
            let predicate = #Predicate<TrackRecord> { $0.id == ownerID }
            guard let owner = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).first else {
                throw ManagedArtworkEditError.missingOwner
            }
            return owner.customArtworkID
        case .playlist:
            let predicate = #Predicate<PlaylistRecord> { $0.id == ownerID }
            guard let owner = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).first else {
                throw ManagedArtworkEditError.missingOwner
            }
            return owner.customArtworkID
        case .smartCollection:
            let predicate = #Predicate<SmartCollectionRecord> {
                $0.id == ownerID
            }
            guard try !modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).isEmpty else {
                throw ManagedArtworkEditError.missingOwner
            }
            return try ownerArtworkRecord(
                ownerKind: ownerKind,
                ownerID: ownerID
            )?.id
        }
    }

    func setOwnerArtworkID(
        _ artworkID: UUID?,
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID
    ) throws {
        switch ownerKind {
        case .artist:
            let predicate = #Predicate<ArtistRecord> { $0.id == ownerID }
            guard let owner = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).first else {
                throw ManagedArtworkEditError.missingOwner
            }
            owner.customArtworkID = artworkID
        case .album:
            let predicate = #Predicate<AlbumRecord> { $0.id == ownerID }
            guard let owner = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).first else {
                throw ManagedArtworkEditError.missingOwner
            }
            owner.customArtworkID = artworkID
        case .track:
            let predicate = #Predicate<TrackRecord> { $0.id == ownerID }
            guard let owner = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).first else {
                throw ManagedArtworkEditError.missingOwner
            }
            owner.customArtworkID = artworkID
        case .playlist:
            let predicate = #Predicate<PlaylistRecord> { $0.id == ownerID }
            guard let owner = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).first else {
                throw ManagedArtworkEditError.missingOwner
            }
            owner.customArtworkID = artworkID
        case .smartCollection:
            let predicate = #Predicate<SmartCollectionRecord> {
                $0.id == ownerID
            }
            guard try !modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).isEmpty else {
                throw ManagedArtworkEditError.missingOwner
            }
        }
    }

    func ownerArtworkRecord(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID
    ) throws -> ArtworkRecord? {
        let rawKind = ownerKind.rawValue
        let predicate = #Predicate<ArtworkRecord> {
            $0.ownerKindRawValue == rawKind && $0.ownerID == ownerID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 2
        let records = try modelContext.fetch(descriptor)
        guard records.count < 2 else {
            throw ManagedArtworkEditError.inconsistentMetadata
        }
        return records.first
    }

    func artworkRecord(id: UUID) throws -> ArtworkRecord? {
        let predicate = #Predicate<ArtworkRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func upsertArtwork(
        _ artwork: ManagedArtworkDescriptor
    ) throws {
        if let existing = try artworkRecord(id: artwork.id) {
            guard
                existing.ownerKind == artwork.ownerKind,
                existing.ownerID == artwork.ownerID,
                existing.relativeOriginalPath == artwork.relativeOriginalPath,
                existing.contentHash == artwork.contentHash
            else {
                throw ManagedArtworkEditError.inconsistentMetadata
            }
            return
        }
        modelContext.insert(
            ArtworkRecord(
                id: artwork.id,
                ownerKind: artwork.ownerKind,
                ownerID: artwork.ownerID,
                relativeOriginalPath: artwork.relativeOriginalPath,
                relativeThumbnailPath: artwork.relativeThumbnailPath,
                format: artwork.format,
                pixelWidth: artwork.pixelWidth,
                pixelHeight: artwork.pixelHeight,
                cropScale: artwork.cropScale,
                normalizedOffsetX: artwork.normalizedOffsetX,
                normalizedOffsetY: artwork.normalizedOffsetY,
                contentHash: artwork.contentHash,
                revision: artwork.revision
            )
        )
    }
}
