import Foundation
import SwiftData

extension LibraryRepository {
    func artwork(
        id: UUID
    ) throws -> ManagedArtworkProjection? {
        let predicate = #Predicate<ArtworkRecord> {
            $0.id == id
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map {
            ManagedArtworkProjection(
                id: $0.id,
                relativePath:
                $0.relativeThumbnailPath ?? $0.relativeOriginalPath,
                revision: $0.revision,
                scale: $0.cropScale,
                normalizedOffsetX: $0.normalizedOffsetX,
                normalizedOffsetY: $0.normalizedOffsetY
            )
        }
    }
}
