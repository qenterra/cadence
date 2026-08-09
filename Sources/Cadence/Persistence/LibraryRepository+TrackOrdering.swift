import Foundation
import SwiftData

extension LibraryRepository {
    func albumTracksInPlaybackOrder(
        albumID: UUID
    ) throws -> [LibraryTrackProjection] {
        let predicate = #Predicate<TrackRecord> {
            $0.album?.id == albumID
        }
        let records = try modelContext.fetch(
            FetchDescriptor(predicate: predicate)
        )
        .sorted(by: Self.albumTrackOrder)
        return try trackProjections(records)
    }

    static func albumTrackOrder(
        lhs: TrackRecord,
        rhs: TrackRecord
    ) -> Bool {
        let lhsDisc = lhs.discNumber ?? 1
        let rhsDisc = rhs.discNumber ?? 1
        if lhsDisc != rhsDisc {
            return lhsDisc < rhsDisc
        }
        let lhsTrack = lhs.trackNumber ?? .max
        let rhsTrack = rhs.trackNumber ?? .max
        if lhsTrack != rhsTrack {
            return lhsTrack < rhsTrack
        }
        if lhs.normalizedTitle != rhs.normalizedTitle {
            return lhs.normalizedTitle < rhs.normalizedTitle
        }
        return lhs.sortIdentity < rhs.sortIdentity
    }

    static func artistTrackOrder(
        lhs: TrackRecord,
        rhs: TrackRecord
    ) -> Bool {
        let lhsAlbum = lhs.album?.normalizedTitle ?? ""
        let rhsAlbum = rhs.album?.normalizedTitle ?? ""
        if lhsAlbum != rhsAlbum {
            return lhsAlbum < rhsAlbum
        }
        return albumTrackOrder(lhs: lhs, rhs: rhs)
    }
}
