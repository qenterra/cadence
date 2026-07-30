import CoreGraphics
import Foundation
import SwiftData

enum ManagedArtworkEditError: Error, LocalizedError, Sendable {
    case invalidImage
    case missingOwner
    case unavailableLibrary

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The selected file is not a supported image."
        case .missingOwner:
            "The selected library item no longer exists."
        case .unavailableLibrary:
            "The managed library is unavailable."
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
    func setArtwork(
        _ request: ManagedArtworkEditRequest,
        location: ManagedLibraryLocation
    ) throws -> UUID {
        guard
            let payload = MetadataReader().artworkPayload(data: request.data)
        else {
            throw ManagedArtworkEditError.invalidImage
        }
        let id = UUID()
        let relativePath = "Artwork/Original/\(id.uuidString)."
            + payload.metadata.format
        let fileURL = try location.resolve(relativePath: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try request.data.write(to: fileURL, options: .atomic)

        do {
            let oldID = try replaceOwnerArtworkID(
                ownerKind: request.ownerKind,
                ownerID: request.ownerID,
                artworkID: id
            )
            let oldArtwork = try oldID.flatMap {
                try artworkRecord(id: $0)
            }
            let oldPaths = artworkPaths(oldArtwork)
            modelContext.insert(
                ArtworkRecord(
                    id: id,
                    ownerKind: request.ownerKind,
                    ownerID: request.ownerID,
                    relativeOriginalPath: relativePath,
                    format: payload.metadata.format,
                    pixelWidth: payload.metadata.pixelWidth,
                    pixelHeight: payload.metadata.pixelHeight,
                    cropScale: Double(request.scale),
                    normalizedOffsetX: request.normalizedOffset.width,
                    normalizedOffsetY: request.normalizedOffset.height,
                    contentHash: payload.metadata.contentHash
                )
            )
            if let oldArtwork {
                modelContext.delete(oldArtwork)
            }
            try modelContext.save()
            removeFiles(at: oldPaths, location: location)
            return id
        } catch {
            modelContext.rollback()
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
    }

    func removeArtwork(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID,
        location: ManagedLibraryLocation
    ) throws {
        let oldID = try replaceOwnerArtworkID(
            ownerKind: ownerKind,
            ownerID: ownerID,
            artworkID: nil
        )
        guard let oldID else {
            return
        }
        guard let oldArtwork = try artworkRecord(id: oldID) else {
            try modelContext.save()
            return
        }
        let oldPaths = artworkPaths(oldArtwork)
        modelContext.delete(oldArtwork)
        do {
            try modelContext.save()
            removeFiles(at: oldPaths, location: location)
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

private extension LibraryRepository {
    func replaceOwnerArtworkID(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID,
        artworkID: UUID?
    ) throws -> UUID? {
        switch ownerKind {
        case .artist:
            let predicate = #Predicate<ArtistRecord> { $0.id == ownerID }
            guard let owner = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).first else {
                throw ManagedArtworkEditError.missingOwner
            }
            let previous = owner.customArtworkID
            owner.customArtworkID = artworkID
            return previous
        case .album:
            let predicate = #Predicate<AlbumRecord> { $0.id == ownerID }
            guard let owner = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).first else {
                throw ManagedArtworkEditError.missingOwner
            }
            let previous = owner.customArtworkID
            owner.customArtworkID = artworkID
            return previous
        case .track:
            let predicate = #Predicate<TrackRecord> { $0.id == ownerID }
            guard let owner = try modelContext.fetch(
                FetchDescriptor(predicate: predicate)
            ).first else {
                throw ManagedArtworkEditError.missingOwner
            }
            let previous = owner.customArtworkID
            owner.customArtworkID = artworkID
            return previous
        }
    }

    func artworkRecord(id: UUID) throws -> ArtworkRecord? {
        let predicate = #Predicate<ArtworkRecord> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func artworkPaths(
        _ artwork: ArtworkRecord?
    ) -> [String] {
        guard let artwork else {
            return []
        }
        return [
            artwork.relativeOriginalPath,
            artwork.relativeThumbnailPath,
        ].compactMap(\.self)
    }

    func removeFiles(
        at paths: [String],
        location: ManagedLibraryLocation
    ) {
        for path in paths {
            guard let url = try? location.resolve(relativePath: path) else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
